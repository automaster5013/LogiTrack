param(
  [string]$Profile = "logitrack-test-admin",
  [string]$Region = "ap-northeast-2",
  [string]$ExpectedAccountId = "816954358294",
  [string]$DomainName = "www.logitrack.kr"
)

$ErrorActionPreference = "Stop"
$env:AWS_PAGER = ""

function Invoke-AwsJson {
  param([Parameter(Mandatory)][string[]]$Arguments)
  $raw = & aws @Arguments --profile $Profile --region $Region --output json --no-cli-pager
  if ($LASTEXITCODE -ne 0) { throw "AWS CLI failed: aws $($Arguments -join ' ')" }
  return ($raw | ConvertFrom-Json)
}

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "AUDIT FAILED: $Message" }
}

$identity = Invoke-AwsJson @("sts", "get-caller-identity")
Assert-True ($identity.Account -eq $ExpectedAccountId) "unexpected AWS account $($identity.Account)"

$instanceResult = Invoke-AwsJson @(
  "ec2", "describe-instances",
  "--filters", "Name=tag:Name,Values=logitrack-staging", "Name=instance-state-name,Values=pending,running,stopping,stopped"
)
$instances = @($instanceResult.Reservations | ForEach-Object { $_.Instances })
Assert-True ($instances.Count -eq 1) "expected exactly one active LogiTrack staging instance"
$instance = $instances[0]
$instanceId = $instance.InstanceId
Assert-True ($instance.State.Name -eq "running") "staging instance is not running"
Assert-True ($instance.InstanceType -eq "t3a.medium") "instance type drifted from t3a.medium"
Assert-True ($instance.MetadataOptions.HttpTokens -eq "required") "IMDSv2 tokens are not required"
Assert-True ($instance.Monitoring.State -eq "disabled") "detailed monitoring unexpectedly enabled"
Assert-True ($instance.IamInstanceProfile.Arn -like "*/logitrack-staging-runtime") "unexpected instance profile"

$termination = Invoke-AwsJson @("ec2", "describe-instance-attribute", "--instance-id", $instanceId, "--attribute", "disableApiTermination")
$shutdown = Invoke-AwsJson @("ec2", "describe-instance-attribute", "--instance-id", $instanceId, "--attribute", "instanceInitiatedShutdownBehavior")
Assert-True ([bool]$termination.DisableApiTermination.Value) "API termination protection is disabled"
Assert-True ($shutdown.InstanceInitiatedShutdownBehavior.Value -eq "stop") "instance shutdown would not stop"

$rootDevice = $instance.RootDeviceName
$rootMapping = @($instance.BlockDeviceMappings | Where-Object DeviceName -eq $rootDevice)
Assert-True ($rootMapping.Count -eq 1) "root EBS mapping is missing"
$volume = Invoke-AwsJson @("ec2", "describe-volumes", "--volume-ids", $rootMapping[0].Ebs.VolumeId)
$rootVolume = @($volume.Volumes)[0]
Assert-True ([bool]$rootVolume.Encrypted) "root EBS volume is not encrypted"
Assert-True ($rootVolume.VolumeType -eq "gp3" -and [int]$rootVolume.Size -eq 30) "root EBS is not 30 GiB gp3"

Assert-True (@($instance.SecurityGroups).Count -eq 1) "instance must have exactly one security group"
$securityGroups = Invoke-AwsJson @("ec2", "describe-security-groups", "--group-ids", $instance.SecurityGroups[0].GroupId)
$ingress = @($securityGroups.SecurityGroups[0].IpPermissions)
Assert-True ($ingress.Count -eq 2) "security group must contain only HTTP and HTTPS ingress"
$ports = @($ingress | ForEach-Object {
  Assert-True ($_.IpProtocol -eq "tcp" -and $_.FromPort -eq $_.ToPort) "ingress must be a single TCP port"
  Assert-True (@($_.IpRanges).Count -eq 1 -and $_.IpRanges[0].CidrIp -eq "0.0.0.0/0") "web ingress CIDR drifted"
  Assert-True (@($_.Ipv6Ranges).Count -eq 0 -and @($_.UserIdGroupPairs).Count -eq 0 -and @($_.PrefixListIds).Count -eq 0) "unexpected ingress source"
  [int]$_.FromPort
} | Sort-Object)
Assert-True (($ports -join ",") -eq "80,443") "only ports 80 and 443 may be public"

$addresses = Invoke-AwsJson @("ec2", "describe-addresses", "--filters", "Name=instance-id,Values=$instanceId")
$publicIp = @($addresses.Addresses)[0].PublicIp
Assert-True (-not [string]::IsNullOrWhiteSpace($publicIp)) "instance has no Elastic IP"
$resolved = @(Resolve-DnsName -Name $DomainName -Type A | Where-Object Type -eq "A" | Select-Object -ExpandProperty IPAddress)
Assert-True ($resolved -contains $publicIp) "DNS does not resolve to the staging Elastic IP"

$alarm = Invoke-AwsJson @("cloudwatch", "describe-alarms", "--alarm-names", "logitrack-staging-ec2-system-recovery")
$metricAlarm = @($alarm.MetricAlarms)[0]
Assert-True ($metricAlarm.StateValue -eq "OK") "EC2 system recovery alarm is not OK"
Assert-True ($metricAlarm.ActionsEnabled -and $metricAlarm.AlarmActions -contains "arn:aws:automate:${Region}:ec2:recover") "EC2 recovery action is missing"
Assert-True ($metricAlarm.Period -eq 60 -and $metricAlarm.EvaluationPeriods -eq 2 -and $metricAlarm.DatapointsToAlarm -eq 2) "recovery alarm timing drifted"

$policies = Invoke-AwsJson @("dlm", "get-lifecycle-policies")
$snapshotPolicy = @($policies.Policies | Where-Object Description -eq "Daily crash-consistent LogiTrack staging root-volume snapshot")
Assert-True ($snapshotPolicy.Count -eq 1) "daily snapshot policy is missing"
$policy = Invoke-AwsJson @("dlm", "get-lifecycle-policy", "--policy-id", $snapshotPolicy[0].PolicyId)
$schedule = $policy.Policy.PolicyDetails.Schedules[0]
Assert-True ($policy.Policy.State -eq "ENABLED" -and $schedule.CreateRule.Times[0] -eq "18:00" -and $schedule.RetainRule.Count -eq 7) "snapshot schedule or retention drifted"

$bucket = "logitrack-staging-backups-$ExpectedAccountId-$Region"
$publicAccess = Invoke-AwsJson @("s3api", "get-public-access-block", "--bucket", $bucket)
$publicFlags = $publicAccess.PublicAccessBlockConfiguration
Assert-True ($publicFlags.BlockPublicAcls -and $publicFlags.IgnorePublicAcls -and $publicFlags.BlockPublicPolicy -and $publicFlags.RestrictPublicBuckets) "backup bucket public access is not fully blocked"
$encryption = Invoke-AwsJson @("s3api", "get-bucket-encryption", "--bucket", $bucket)
Assert-True ($encryption.ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm -eq "AES256") "backup bucket encryption drifted"
$lifecycle = Invoke-AwsJson @("s3api", "get-bucket-lifecycle-configuration", "--bucket", $bucket)
$backupRule = @($lifecycle.Rules | Where-Object Id -eq "expire-postgres-backups")[0]
Assert-True ($backupRule.Status -eq "Enabled" -and $backupRule.Expiration.Days -eq 8) "backup expiration drifted"
$objects = Invoke-AwsJson @("s3api", "list-objects-v2", "--bucket", $bucket, "--prefix", "postgres/", "--max-items", "1")
$backupObjects = @($objects.Contents)
Assert-True ($backupObjects.Count -eq 1 -and $backupObjects[0].Size -gt 0) "no non-empty off-host PostgreSQL backup exists"
$backupObject = Invoke-AwsJson @("s3api", "head-object", "--bucket", $bucket, "--key", $backupObjects[0].Key)
Assert-True ($backupObject.ServerSideEncryption -eq "AES256") "latest PostgreSQL backup is not AES256 encrypted"

$associations = Invoke-AwsJson @("ssm", "list-associations", "--association-filter-list", "key=AssociationName,value=logitrack-staging-postgres-backup")
$association = @($associations.Associations)
Assert-True ($association.Count -eq 1 -and $association[0].Overview.Status -eq "Success") "PostgreSQL backup association is not successful"

$budget = & aws budgets describe-budget --profile $Profile --account-id $ExpectedAccountId --budget-name logitrack-staging-monthly --output json --no-cli-pager
if ($LASTEXITCODE -ne 0) { throw "AWS CLI failed while reading the staging budget" }
$budgetValue = $budget | ConvertFrom-Json
Assert-True ($budgetValue.Budget.BudgetLimit.Amount -eq "70.0" -and $budgetValue.Budget.BudgetLimit.Unit -eq "USD" -and $budgetValue.Budget.TimeUnit -eq "MONTHLY") "monthly USD 70 budget drifted"
$notificationsRaw = & aws budgets describe-notifications-for-budget --profile $Profile --account-id $ExpectedAccountId --budget-name logitrack-staging-monthly --output json --no-cli-pager
if ($LASTEXITCODE -ne 0) { throw "AWS CLI failed while reading budget notifications" }
$notifications = @(($notificationsRaw | ConvertFrom-Json).Notifications)
$actualAlert = @($notifications | Where-Object { $_.NotificationType -eq "ACTUAL" -and $_.ComparisonOperator -eq "GREATER_THAN" -and $_.Threshold -eq 80 })
$forecastAlert = @($notifications | Where-Object { $_.NotificationType -eq "FORECASTED" -and $_.ComparisonOperator -eq "GREATER_THAN" -and $_.Threshold -eq 100 })
Assert-True ($notifications.Count -eq 2 -and $actualAlert.Count -eq 1 -and $forecastAlert.Count -eq 1) "budget notification thresholds drifted"

Write-Output "PASS: AWS staging runtime audit succeeded for $instanceId ($publicIp)"
