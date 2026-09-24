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
  $profileArguments = if ([string]::IsNullOrWhiteSpace($Profile)) { @() } else { @("--profile", $Profile) }
  $raw = & aws @Arguments @profileArguments --region $Region --output json --no-cli-pager
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
    [Parameter(Mandatory)][hashtable]$ExpectedActionResources,
    [string]$ExpectedServicePrincipal,
    [string]$ExpectedOidcSubject
  )
  $role = Invoke-AwsJson @("iam", "get-role", "--role-name", $RoleName)
  $trustStatements = @($role.Role.AssumeRolePolicyDocument.Statement)
  Assert-True ($trustStatements.Count -eq 1) "$RoleName must have exactly one trust statement"
  $trust = $trustStatements[0]
  Assert-True ($null -eq $trust.NotAction -and $null -eq $trust.NotPrincipal) "$RoleName trust policy contains a negative selector"
  if ($ExpectedServicePrincipal) {
    Assert-True ($trust.Effect -eq "Allow" -and $trust.Action -eq "sts:AssumeRole" -and $trust.Principal.Service -eq $ExpectedServicePrincipal -and $null -eq $trust.Condition) "$RoleName trust policy drifted"
  } else {
    $expectedProvider = "arn:aws:iam::${ExpectedAccountId}:oidc-provider/token.actions.githubusercontent.com"
    Assert-True ($trust.Effect -eq "Allow" -and $trust.Action -eq "sts:AssumeRoleWithWebIdentity" -and $trust.Principal.Federated -eq $expectedProvider) "$RoleName OIDC principal drifted"
    Assert-True (@($trust.Condition.PSObject.Properties).Count -eq 1 -and @($trust.Condition.StringEquals.PSObject.Properties).Count -eq 2) "$RoleName OIDC condition set drifted"
    Assert-True ($trust.Condition.StringEquals.'token.actions.githubusercontent.com:aud' -eq "sts.amazonaws.com") "$RoleName OIDC audience drifted"
    Assert-True ($trust.Condition.StringEquals.'token.actions.githubusercontent.com:sub' -eq $ExpectedOidcSubject) "$RoleName OIDC subject drifted"
  }
  $attached = Invoke-AwsJson @("iam", "list-attached-role-policies", "--role-name", $RoleName)
  $attachedArns = @($attached.AttachedPolicies.PolicyArn | Sort-Object)
  Assert-True (($attachedArns -join ",") -eq (($ExpectedAttachedPolicies | Sort-Object) -join ",")) "$RoleName attached policies drifted"
  $inline = Invoke-AwsJson @("iam", "list-role-policies", "--role-name", $RoleName)
  Assert-True (@($inline.PolicyNames).Count -eq 1 -and $inline.PolicyNames[0] -eq $ExpectedInlinePolicy) "$RoleName inline policy set drifted"
  $policy = Invoke-AwsJson @("iam", "get-role-policy", "--role-name", $RoleName, "--policy-name", $ExpectedInlinePolicy)
  $statements = @($policy.PolicyDocument.Statement)
  Assert-True ($statements.Count -gt 0 -and @($statements | Where-Object { $_.Effect -ne "Allow" -or $null -ne $_.NotAction -or $null -ne $_.NotResource -or $null -ne $_.Principal }).Count -eq 0) "$RoleName inline policy contains an unexpected statement shape"
  $actions = @($statements | ForEach-Object { @($_.Action) } | Sort-Object -Unique)
  Assert-True (($actions -join ",") -eq (($ExpectedActions | Sort-Object -Unique) -join ",")) "$RoleName allowed actions drifted"
  Assert-True ((@($ExpectedActionResources.Keys | Sort-Object) -join ",") -eq (@($ExpectedActions | Sort-Object -Unique) -join ",")) "$RoleName audit resource expectations are incomplete"
  foreach ($action in $ExpectedActions) {
    $actualResources = @($statements | Where-Object { @($_.Action) -contains $action } | ForEach-Object { @($_.Resource) } | Sort-Object -Unique)
    $expectedResources = @($ExpectedActionResources[$action] | Sort-Object -Unique)
    Assert-True (($actualResources -join ",") -eq ($expectedResources -join ",")) "$RoleName resource scope drifted for $action"
  }
  return $policy.PolicyDocument
}

$identity = Invoke-AwsJson @("sts", "get-caller-identity")
Assert-True ($identity.Account -eq $ExpectedAccountId) "unexpected AWS account $($identity.Account)"
$oidcSubject = "repo:automaster5013@247691206/LogiTrack@1376500287:environment:staging"
$expectedInstanceId = "i-07de6c372fc44e964"
$expectedRepositories = @("api", "analytics", "simulator", "web", "otel-collector" | ForEach-Object { "arn:aws:ecr:${Region}:${ExpectedAccountId}:repository/logitrack/$_" })
$expectedParameters = @("postgres-password", "cognito-issuer-uri", "cognito-client-id", "cognito-authorization-base-url" | ForEach-Object { "arn:aws:ssm:${Region}:${ExpectedAccountId}:parameter/logitrack/staging/$_" })
$expectedBackupBucket = "arn:aws:s3:::logitrack-staging-backups-${ExpectedAccountId}-${Region}"

$runtimeResources = @{}
foreach ($action in @("ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer")) { $runtimeResources[$action] = $expectedRepositories }
foreach ($action in @("ssm:GetParameter", "ssm:GetParameters")) { $runtimeResources[$action] = $expectedParameters }
foreach ($action in @("s3:PutObject", "s3:GetObject")) { $runtimeResources[$action] = "$expectedBackupBucket/postgres/*" }
$runtimeResources["ecr:GetAuthorizationToken"] = "*"
$runtimeResources["s3:ListBucket"] = $expectedBackupBucket
$runtimePolicy = Assert-RoleBoundary -RoleName "logitrack-staging-runtime" `
  -ExpectedAttachedPolicies @("arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore") `
  -ExpectedInlinePolicy "pull-images-and-read-runtime-secrets" `
  -ExpectedActions @("ecr:GetAuthorizationToken", "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ssm:GetParameter", "ssm:GetParameters", "s3:PutObject", "s3:GetObject", "s3:ListBucket") `
  -ExpectedActionResources $runtimeResources `
  -ExpectedServicePrincipal "ec2.amazonaws.com"
$listBucketStatement = @($runtimePolicy.Statement | Where-Object { @($_.Action) -contains "s3:ListBucket" })
Assert-True ($listBucketStatement.Count -eq 1 -and @($listBucketStatement[0].Condition.PSObject.Properties).Count -eq 1 -and $listBucketStatement[0].Condition.StringLike.'s3:prefix' -eq "postgres/*") "runtime backup bucket prefix condition drifted"

$deployerResources = @{
  "ecr:DescribeImages"               = $expectedRepositories
  "ssm:SendCommand"                  = @("arn:aws:ssm:${Region}::document/AWS-RunShellScript", "arn:aws:ec2:${Region}:${ExpectedAccountId}:instance/$expectedInstanceId")
  "ssm:GetCommandInvocation"         = "*"
  "ssm:ListCommandInvocations"       = "*"
  "ec2:DescribeInstances"            = "*"
  "ssm:DescribeInstanceInformation"  = "*"
}
$null = Assert-RoleBoundary -RoleName "logitrack-staging-runtime-deployer" `
  -ExpectedAttachedPolicies @() `
  -ExpectedInlinePolicy "deploy-only-to-logitrack-staging" `
  -ExpectedActions @("ecr:DescribeImages", "ssm:SendCommand", "ssm:GetCommandInvocation", "ssm:ListCommandInvocations", "ec2:DescribeInstances", "ssm:DescribeInstanceInformation") `
  -ExpectedActionResources $deployerResources `
  -ExpectedOidcSubject $oidcSubject

$publisherActions = @("ecr:DescribeRepositories", "ecr:GetAuthorizationToken", "ecr:BatchGetImage", "ecr:BatchCheckLayerAvailability", "ecr:CompleteLayerUpload", "ecr:DescribeImages", "ecr:GetDownloadUrlForLayer", "ecr:GetLifecyclePolicy", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart")
$publisherResources = @{}
foreach ($action in $publisherActions) { $publisherResources[$action] = if ($action -in @("ecr:DescribeRepositories", "ecr:GetAuthorizationToken")) { "*" } else { $expectedRepositories } }
$null = Assert-RoleBoundary -RoleName "logitrack-staging-image-publisher" `
  -ExpectedAttachedPolicies @() `
  -ExpectedInlinePolicy "publish-logitrack-staging-images" `
  -ExpectedActions $publisherActions `
  -ExpectedActionResources $publisherResources `
  -ExpectedOidcSubject $oidcSubject

$auditOidcSubject = "repo:automaster5013@247691206/LogiTrack@1376500287:ref:refs/heads/main"
$auditorActions = @(
  "acm:DescribeCertificate", "cloudwatch:DescribeAlarms",
  "cognito-idp:DescribeManagedLoginBrandingByClient", "cognito-idp:DescribeUserPool", "cognito-idp:DescribeUserPoolClient", "cognito-idp:DescribeUserPoolDomain",
  "cognito-idp:GetUserPoolMfaConfig", "cognito-idp:ListGroups", "cognito-idp:ListUserPoolClients", "cognito-idp:ListUserPools", "cognito-idp:ListUsers", "cognito-idp:ListUsersInGroup",
  "dlm:GetLifecyclePolicies", "dlm:GetLifecyclePolicy",
  "ec2:DescribeAddresses", "ec2:DescribeInstanceAttribute", "ec2:DescribeInstances", "ec2:DescribeSecurityGroups", "ec2:DescribeSnapshots", "ec2:DescribeVolumes",
  "ssm:DescribeAssociation", "ssm:DescribeInstanceInformation", "ssm:ListAssociations", "sts:GetCallerIdentity",
  "iam:GetRole", "iam:GetRolePolicy", "iam:ListAttachedRolePolicies", "iam:ListRolePolicies",
  "ecr:DescribeRepositories", "ecr:GetLifecyclePolicy",
  "s3:GetBucketEncryption", "s3:GetBucketLifecycleConfiguration", "s3:GetBucketPublicAccessBlock", "s3:ListBucket", "s3:GetObject",
  "route53:ListResourceRecordSets"
)
$auditorResources = @{}
foreach ($action in $auditorActions) { $auditorResources[$action] = "*" }
foreach ($action in @("iam:GetRole", "iam:GetRolePolicy", "iam:ListAttachedRolePolicies", "iam:ListRolePolicies")) { $auditorResources[$action] = "arn:aws:iam::${ExpectedAccountId}:role/logitrack-staging-*" }
foreach ($action in @("ecr:DescribeRepositories", "ecr:GetLifecyclePolicy")) { $auditorResources[$action] = $expectedRepositories }
foreach ($action in @("s3:GetBucketEncryption", "s3:GetBucketLifecycleConfiguration", "s3:GetBucketPublicAccessBlock", "s3:ListBucket")) { $auditorResources[$action] = $expectedBackupBucket }
$auditorResources["s3:GetObject"] = "$expectedBackupBucket/postgres/*"
$auditorResources["route53:ListResourceRecordSets"] = "arn:aws:route53:::hostedzone/Z05031871LL3C3WCCPUJO"
$null = Assert-RoleBoundary -RoleName "logitrack-staging-boundary-auditor" `
  -ExpectedAttachedPolicies @() `
  -ExpectedInlinePolicy "audit-logitrack-staging-boundaries" `
  -ExpectedActions $auditorActions `
  -ExpectedActionResources $auditorResources `
  -ExpectedOidcSubject $auditOidcSubject

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

$managedNodes = Invoke-AwsJson @("ssm", "describe-instance-information", "--filters", "Key=InstanceIds,Values=$instanceId")
$managedNode = @($managedNodes.InstanceInformationList)
Assert-True ($managedNode.Count -eq 1) "staging instance is not registered as exactly one SSM managed node"
$lastPingAge = [DateTimeOffset]::UtcNow - [DateTimeOffset]::Parse([string]$managedNode[0].LastPingDateTime)
Assert-True ($managedNode[0].PingStatus -eq "Online" -and $lastPingAge.TotalMinutes -ge -5 -and $lastPingAge.TotalMinutes -le 15) "staging SSM agent is offline or stale"
Assert-True ($managedNode[0].ResourceType -eq "EC2Instance" -and $managedNode[0].PlatformType -eq "Linux" -and $managedNode[0].PlatformName -eq "Amazon Linux") "staging SSM managed-node identity drifted"
Assert-True ($managedNode[0].IPAddress -eq $instance.PrivateIpAddress -and $managedNode[0].AssociationStatus -eq "Success") "staging SSM address or association status drifted"

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
Assert-True ($schedule.CopyTags -and @($schedule.TagsToAdd).Count -eq 1 -and $schedule.TagsToAdd[0].Key -eq "BackupType" -and $schedule.TagsToAdd[0].Value -eq "crash-consistent") "snapshot tags contain a duplicate source-volume key or lost the backup marker"
$now = [DateTimeOffset]::UtcNow
$snapshotsResult = Invoke-AwsJson @("ec2", "describe-snapshots", "--owner-ids", "self", "--filters", "Name=volume-id,Values=$($rootVolume.VolumeId)", "Name=status,Values=completed")
$managedSnapshots = @($snapshotsResult.Snapshots | Where-Object {
  $tags = @{}; foreach ($tag in @($_.Tags)) { $tags[$tag.Key] = $tag.Value }
  $tags.SnapshotSchedule -eq "logitrack-staging-daily" -and $tags.BackupType -eq "crash-consistent"
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
$backupObject = Invoke-AwsJson @("s3api", "head-object", "--bucket", $bucket, "--key", $latestBackup.Key, "--checksum-mode", "ENABLED")
Assert-True ($backupObject.ServerSideEncryption -eq "AES256") "latest PostgreSQL backup is not AES256 encrypted"
Assert-True (-not [string]::IsNullOrWhiteSpace([string]$backupObject.ChecksumSHA256)) "latest PostgreSQL backup has no stored SHA-256 checksum"

$associations = Invoke-AwsJson @("ssm", "list-associations", "--association-filter-list", "key=AssociationName,value=logitrack-staging-postgres-backup")
$association = @($associations.Associations)
Assert-True ($association.Count -eq 1 -and $association[0].Overview.Status -eq "Success") "PostgreSQL backup association is not successful"
$associationResult = Invoke-AwsJson @("ssm", "describe-association", "--association-id", $association[0].AssociationId)
$backupAssociation = $associationResult.AssociationDescription
$backupTargets = @($backupAssociation.Targets)
Assert-True ($backupAssociation.Name -eq "AWS-RunShellScript" -and $backupAssociation.AssociationName -eq "logitrack-staging-postgres-backup") "PostgreSQL backup association identity drifted"
Assert-True ($backupAssociation.ScheduleExpression -eq "cron(30 18 * * ? *)" -and $backupAssociation.ApplyOnlyAtCronInterval -and $backupAssociation.MaxConcurrency -eq "1" -and $backupAssociation.MaxErrors -eq "0" -and $backupAssociation.ComplianceSeverity -eq "HIGH") "PostgreSQL backup association schedule or failure boundary drifted"
Assert-True ($backupTargets.Count -eq 1 -and $backupTargets[0].Key -eq "InstanceIds" -and @($backupTargets[0].Values).Count -eq 1 -and $backupTargets[0].Values[0] -eq $instanceId) "PostgreSQL backup association targets an unexpected managed node"
$backupCommand = [string]$backupAssociation.Parameters.commands[0]
Assert-True ($backupCommand.Contains("pg_restore --list") -and $backupCommand.Contains("pg_restore --exit-on-error --no-owner --no-privileges") -and $backupCommand.Contains("information_schema.tables") -and $backupCommand.Contains("dropdb --if-exists --force") -and $backupCommand.Contains("--sse AES256 --checksum-algorithm SHA256") -and $backupCommand.Contains("s3://$bucket/")) "PostgreSQL backup association lost restore validation, checksum, or encryption"

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
