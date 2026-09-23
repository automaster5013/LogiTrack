param(
  [string]$Profile = "logitrack-test-admin",
  [string]$Region = "ap-northeast-2",
  [string]$ExpectedAccountId = "816954358294",
  [string]$DomainName = "www.logitrack.kr",
  [ValidateRange(25, 72)][int]$MaximumBackupAgeHours = 30
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

function Resolve-Ipv4WithRetry {
  param([Parameter(Mandatory)][string]$Name)
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
      $addresses = @(Resolve-DnsName -Name $Name -Type A -ErrorAction Stop | Where-Object Type -eq "A" | Select-Object -ExpandProperty IPAddress)
      if ($addresses.Count -gt 0) { return $addresses }
    } catch {
      if ($attempt -eq 3) { throw "AUDIT FAILED: DNS lookup failed after 3 attempts: $($_.Exception.Message)" }
    }
    Start-Sleep -Seconds 2
  }
  throw "AUDIT FAILED: DNS returned no IPv4 address after 3 attempts"
}

function Assert-RoleBoundary {
  param(
    [Parameter(Mandatory)][string]$RoleName,
    [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ExpectedAttachedPolicies,
    [Parameter(Mandatory)][string]$ExpectedInlinePolicy,
    [Parameter(Mandatory)][string[]]$ExpectedActions,
    [string]$ExpectedServicePrincipal,
    [string]$ExpectedOidcSubject
  )
  $role = Invoke-AwsJson @("iam", "get-role", "--role-name", $RoleName)
  $trust = $role.Role.AssumeRolePolicyDocument.Statement[0]
  if ($ExpectedServicePrincipal) {
    Assert-True ($trust.Effect -eq "Allow" -and $trust.Action -eq "sts:AssumeRole" -and $trust.Principal.Service -eq $ExpectedServicePrincipal) "$RoleName trust policy drifted"
  } else {
    $expectedProvider = "arn:aws:iam::${ExpectedAccountId}:oidc-provider/token.actions.githubusercontent.com"
    Assert-True ($trust.Effect -eq "Allow" -and $trust.Action -eq "sts:AssumeRoleWithWebIdentity" -and $trust.Principal.Federated -eq $expectedProvider) "$RoleName OIDC principal drifted"
    Assert-True ($trust.Condition.StringEquals.'token.actions.githubusercontent.com:aud' -eq "sts.amazonaws.com") "$RoleName OIDC audience drifted"
    Assert-True ($trust.Condition.StringEquals.'token.actions.githubusercontent.com:sub' -eq $ExpectedOidcSubject) "$RoleName OIDC subject drifted"
  }
  $attached = Invoke-AwsJson @("iam", "list-attached-role-policies", "--role-name", $RoleName)
  $attachedArns = @($attached.AttachedPolicies.PolicyArn | Sort-Object)
  Assert-True (($attachedArns -join ",") -eq (($ExpectedAttachedPolicies | Sort-Object) -join ",")) "$RoleName attached policies drifted"
  $inline = Invoke-AwsJson @("iam", "list-role-policies", "--role-name", $RoleName)
  Assert-True (@($inline.PolicyNames).Count -eq 1 -and $inline.PolicyNames[0] -eq $ExpectedInlinePolicy) "$RoleName inline policy set drifted"
  $policy = Invoke-AwsJson @("iam", "get-role-policy", "--role-name", $RoleName, "--policy-name", $ExpectedInlinePolicy)
  $actions = @($policy.PolicyDocument.Statement | ForEach-Object { @($_.Action) } | Sort-Object -Unique)
  Assert-True (($actions -join ",") -eq (($ExpectedActions | Sort-Object -Unique) -join ",")) "$RoleName allowed actions drifted"
}

$identity = Invoke-AwsJson @("sts", "get-caller-identity")
Assert-True ($identity.Account -eq $ExpectedAccountId) "unexpected AWS account $($identity.Account)"
$oidcSubject = "repo:automaster5013@247691206/LogiTrack@1376500287:environment:staging"
Assert-RoleBoundary -RoleName "logitrack-staging-runtime" `
  -ExpectedAttachedPolicies @("arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore") `
  -ExpectedInlinePolicy "pull-images-and-read-runtime-secrets" `
  -ExpectedActions @("ecr:GetAuthorizationToken", "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ssm:GetParameter", "ssm:GetParameters", "s3:PutObject", "s3:GetObject", "s3:ListBucket") `
  -ExpectedServicePrincipal "ec2.amazonaws.com"
Assert-RoleBoundary -RoleName "logitrack-staging-runtime-deployer" `
  -ExpectedAttachedPolicies @() `
  -ExpectedInlinePolicy "deploy-only-to-logitrack-staging" `
  -ExpectedActions @("ecr:DescribeImages", "ssm:SendCommand", "ssm:GetCommandInvocation", "ssm:ListCommandInvocations", "ec2:DescribeInstances", "ssm:DescribeInstanceInformation") `
  -ExpectedOidcSubject $oidcSubject
Assert-RoleBoundary -RoleName "logitrack-staging-image-publisher" `
  -ExpectedAttachedPolicies @() `
  -ExpectedInlinePolicy "publish-logitrack-staging-images" `
  -ExpectedActions @("ecr:DescribeRepositories", "ecr:GetAuthorizationToken", "ecr:BatchGetImage", "ecr:BatchCheckLayerAvailability", "ecr:CompleteLayerUpload", "ecr:DescribeImages", "ecr:GetDownloadUrlForLayer", "ecr:GetLifecyclePolicy", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart") `
  -ExpectedOidcSubject $oidcSubject

$services = @("api", "analytics", "simulator", "web", "otel-collector")
$repositoryNames = @($services | ForEach-Object { "logitrack/$_" })
$repositoryArguments = @("ecr", "describe-repositories", "--repository-names") + $repositoryNames
$repositories = Invoke-AwsJson -Arguments $repositoryArguments
Assert-True (@($repositories.Repositories).Count -eq 5) "expected exactly five LogiTrack ECR repositories"
foreach ($repositoryName in $repositoryNames) {
  $repository = @($repositories.Repositories | Where-Object RepositoryName -eq $repositoryName)
  Assert-True ($repository.Count -eq 1) "ECR repository is missing: $repositoryName"
  Assert-True ($repository[0].ImageTagMutability -eq "IMMUTABLE") "$repositoryName tags are not immutable"
  Assert-True ([bool]$repository[0].ImageScanningConfiguration.ScanOnPush) "$repositoryName scan-on-push is disabled"
  Assert-True ($repository[0].EncryptionConfiguration.EncryptionType -eq "AES256") "$repositoryName encryption drifted"
  $lifecycleResult = Invoke-AwsJson @("ecr", "get-lifecycle-policy", "--repository-name", $repositoryName)
  $lifecyclePolicy = $lifecycleResult.LifecyclePolicyText | ConvertFrom-Json
  $rules = @($lifecyclePolicy.rules | Sort-Object rulePriority)
  Assert-True ($rules.Count -eq 2) "$repositoryName lifecycle rule count drifted"
  Assert-True ($rules[0].rulePriority -eq 1 -and $rules[0].selection.tagStatus -eq "untagged" -and $rules[0].selection.countType -eq "sinceImagePushed" -and $rules[0].selection.countUnit -eq "days" -and $rules[0].selection.countNumber -eq 7 -and $rules[0].action.type -eq "expire") "$repositoryName untagged retention drifted"
  Assert-True ($rules[1].rulePriority -eq 2 -and $rules[1].selection.tagStatus -eq "any" -and $rules[1].selection.countType -eq "imageCountMoreThan" -and $rules[1].selection.countNumber -eq 30 -and $rules[1].action.type -eq "expire") "$repositoryName rollback retention drifted"
}

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
$resolved = @(Resolve-Ipv4WithRetry -Name $DomainName)
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
$now = [DateTimeOffset]::UtcNow
$snapshotsResult = Invoke-AwsJson @("ec2", "describe-snapshots", "--owner-ids", "self", "--filters", "Name=volume-id,Values=$($rootVolume.VolumeId)", "Name=status,Values=completed")
$managedSnapshots = @($snapshotsResult.Snapshots | Where-Object {
  $tags = @{}; foreach ($tag in @($_.Tags)) { $tags[$tag.Key] = $tag.Value }
  $tags.Name -eq "logitrack-staging-daily" -and $tags.BackupType -eq "crash-consistent"
} | Sort-Object { [DateTimeOffset]::Parse([string]$_.StartTime) } -Descending)
if ($managedSnapshots.Count -eq 0) {
  $policyAge = $now - [DateTimeOffset]::Parse([string]$policy.Policy.DateCreated)
  Assert-True ($policyAge.TotalHours -le $MaximumBackupAgeHours) "no managed EBS snapshot exists after the initial schedule grace period"
  Write-Output "INFO: first managed EBS snapshot is still within the initial schedule grace period"
} else {
  $latestSnapshot = $managedSnapshots[0]
  $snapshotAge = $now - [DateTimeOffset]::Parse([string]$latestSnapshot.StartTime)
  Assert-True ([bool]$latestSnapshot.Encrypted) "latest managed EBS snapshot is not encrypted"
  Assert-True ($snapshotAge.TotalMinutes -ge -5 -and $snapshotAge.TotalHours -le $MaximumBackupAgeHours) "latest managed EBS snapshot is stale or future-dated"
}

$bucket = "logitrack-staging-backups-$ExpectedAccountId-$Region"
$publicAccess = Invoke-AwsJson @("s3api", "get-public-access-block", "--bucket", $bucket)
$publicFlags = $publicAccess.PublicAccessBlockConfiguration
Assert-True ($publicFlags.BlockPublicAcls -and $publicFlags.IgnorePublicAcls -and $publicFlags.BlockPublicPolicy -and $publicFlags.RestrictPublicBuckets) "backup bucket public access is not fully blocked"
$encryption = Invoke-AwsJson @("s3api", "get-bucket-encryption", "--bucket", $bucket)
Assert-True ($encryption.ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm -eq "AES256") "backup bucket encryption drifted"
$lifecycle = Invoke-AwsJson @("s3api", "get-bucket-lifecycle-configuration", "--bucket", $bucket)
$backupRule = @($lifecycle.Rules | Where-Object Id -eq "expire-postgres-backups")[0]
Assert-True ($backupRule.Status -eq "Enabled" -and $backupRule.Expiration.Days -eq 8) "backup expiration drifted"
$objects = Invoke-AwsJson @("s3api", "list-objects-v2", "--bucket", $bucket, "--prefix", "postgres/")
$backupObjects = @($objects.Contents | Sort-Object { [DateTimeOffset]::Parse([string]$_.LastModified) } -Descending)
Assert-True ($backupObjects.Count -ge 1 -and $backupObjects[0].Size -gt 0) "no non-empty off-host PostgreSQL backup exists"
$latestBackup = $backupObjects[0]
$backupAge = $now - [DateTimeOffset]::Parse([string]$latestBackup.LastModified)
Assert-True ($backupAge.TotalMinutes -ge -5 -and $backupAge.TotalHours -le $MaximumBackupAgeHours) "latest PostgreSQL backup is stale or future-dated"
$backupObject = Invoke-AwsJson @("s3api", "head-object", "--bucket", $bucket, "--key", $latestBackup.Key)
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
