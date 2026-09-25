param(
  [string]$Owner = "automaster5013",
  [string]$Repository = "LogiTrack",
  [string]$Environment = "staging"
)

$ErrorActionPreference = "Stop"
$credentialInput = "protocol=https`nhost=github.com`n`n"
$credentialLines = $credentialInput | git credential fill
$credential = @{}
foreach ($line in $credentialLines) {
  if ($line -match '^([^=]+)=(.*)$') { $credential[$matches[1]] = $matches[2] }
}
if (-not $credential.password) { throw "AUDIT FAILED: GitHub credential is unavailable" }
$headers = @{
  Authorization = "Bearer $($credential.password)"
  Accept = "application/vnd.github+json"
  "X-GitHub-Api-Version" = "2022-11-28"
}
$baseUri = "https://api.github.com/repos/$Owner/$Repository"

function Invoke-GitHubGet {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Path)
  return Invoke-RestMethod -Method Get -Uri "$baseUri$Path" -Headers $headers
}

function Get-GitHubStatus {
  param([Parameter(Mandatory)][string]$Path)
  $response = Invoke-WebRequest -Method Get -Uri "$baseUri$Path" -Headers $headers
  return [int]$response.StatusCode
}

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "AUDIT FAILED: $Message" }
}

$repositoryInfo = Invoke-GitHubGet ""
Assert-True ($repositoryInfo.id -eq 1376500287 -and $repositoryInfo.owner.id -eq 247691206 -and $repositoryInfo.default_branch -eq "main") "repository identity or default branch drifted"
Assert-True ($repositoryInfo.allow_squash_merge -and -not $repositoryInfo.allow_merge_commit -and -not $repositoryInfo.allow_rebase_merge) "repository must allow squash merge only"
Assert-True ($repositoryInfo.delete_branch_on_merge -and -not $repositoryInfo.allow_auto_merge) "merged branches must be deleted without automatic merging"
$security = $repositoryInfo.security_and_analysis
Assert-True ($security.secret_scanning.status -eq "enabled" -and $security.secret_scanning_push_protection.status -eq "enabled") "secret scanning or push protection is disabled"
Assert-True ($security.dependabot_security_updates.status -eq "enabled") "Dependabot security updates are disabled"
$privateVulnerabilityReporting = Invoke-GitHubGet "/private-vulnerability-reporting"
Assert-True ($privateVulnerabilityReporting.enabled) "private vulnerability reporting is disabled"
Assert-True ((Get-GitHubStatus "/vulnerability-alerts") -eq 204 -and (Get-GitHubStatus "/automated-security-fixes") -eq 200) "Dependabot alerts or automated security fixes are disabled"
$dependabotAlerts = @((Invoke-GitHubGet "/dependabot/alerts?state=open&per_page=100") | Where-Object { $null -ne $_ })
$highRiskAlerts = @($dependabotAlerts | Where-Object { $_.security_advisory.severity -in @("critical", "high") })
Assert-True ($highRiskAlerts.Count -eq 0) "open critical or high Dependabot alerts require remediation"
$secretAlerts = @((Invoke-GitHubGet "/secret-scanning/alerts?state=open&per_page=100") | Where-Object { $null -ne $_ })
Assert-True ($secretAlerts.Count -eq 0) "open secret scanning alerts require remediation"
$codeScanning = Invoke-GitHubGet "/code-scanning/default-setup"
$codeLanguages = @($codeScanning.languages | Sort-Object)
$expectedCodeLanguages = @("actions", "java-kotlin", "javascript", "javascript-typescript", "python", "typescript") | Sort-Object
Assert-True ($codeScanning.state -eq "configured" -and $codeScanning.query_suite -eq "extended" -and $codeScanning.threat_model -eq "remote") "CodeQL default setup drifted"
Assert-True ($codeScanning.runner_type -eq "standard" -and $codeScanning.schedule -eq "weekly" -and ($codeLanguages -join ",") -eq ($expectedCodeLanguages -join ",")) "CodeQL language, runner, or schedule drifted"
$codeAlerts = @((Invoke-GitHubGet "/code-scanning/alerts?state=open&per_page=100") | Where-Object { $null -ne $_ })
$highRiskCodeAlerts = @($codeAlerts | Where-Object { $_.rule.security_severity_level -in @("critical", "high") })
Assert-True ($highRiskCodeAlerts.Count -eq 0) "open critical or high CodeQL alerts require remediation"

$actions = Invoke-GitHubGet "/actions/permissions"
Assert-True ($actions.enabled -and $actions.sha_pinning_required) "Actions must be enabled and require full commit SHA pinning"
$workflowPermissions = Invoke-GitHubGet "/actions/permissions/workflow"
Assert-True ($workflowPermissions.default_workflow_permissions -eq "read" -and -not $workflowPermissions.can_approve_pull_request_reviews) "default workflow token permissions are too broad"

$mainProtection = Invoke-GitHubGet "/branches/main/protection"
$requiredChecks = @($mainProtection.required_status_checks.contexts | Sort-Object)
$expectedChecks = @("API tests and domain coverage", "Dependency vulnerability review", "Production images and supply-chain security", "Python tests and Compose validation", "TypeScript production build") | Sort-Object
Assert-True ($mainProtection.required_status_checks.strict -and ($requiredChecks -join ",") -eq ($expectedChecks -join ",")) "main required CI checks drifted"
Assert-True ($mainProtection.enforce_admins.enabled) "administrators may bypass main protection"
Assert-True ($mainProtection.required_linear_history.enabled -and $mainProtection.required_conversation_resolution.enabled) "main history or conversation protection drifted"
Assert-True (-not $mainProtection.allow_force_pushes.enabled -and -not $mainProtection.allow_deletions.enabled) "main permits force pushes or deletion"
$pullRequestRule = $mainProtection.required_pull_request_reviews
Assert-True ($null -ne $pullRequestRule -and $pullRequestRule.required_approving_review_count -eq 0) "main changes must pass through a pull request without blocking solo maintenance"
Assert-True ($pullRequestRule.dismiss_stale_reviews -and -not $pullRequestRule.require_code_owner_reviews -and -not $pullRequestRule.require_last_push_approval) "main pull request review policy drifted"

$environmentInfo = Invoke-GitHubGet "/environments/$Environment"
Assert-True (-not $environmentInfo.deployment_branch_policy.protected_branches -and $environmentInfo.deployment_branch_policy.custom_branch_policies) "staging must use an explicit deployment branch policy"
$reviewRule = @($environmentInfo.protection_rules | Where-Object type -eq "required_reviewers")
$branchRule = @($environmentInfo.protection_rules | Where-Object type -eq "branch_policy")
Assert-True ($reviewRule.Count -eq 1 -and $branchRule.Count -eq 1) "staging protection rules drifted"
$reviewers = @($reviewRule[0].reviewers)
Assert-True ($reviewers.Count -eq 1 -and $reviewers[0].type -eq "User" -and $reviewers[0].reviewer.id -eq 247691206 -and $reviewers[0].reviewer.login -eq $Owner) "staging required reviewer drifted"

$branches = Invoke-GitHubGet "/environments/$Environment/deployment-branch-policies?per_page=100"
$branchPolicies = @($branches.branch_policies)
Assert-True ($branchPolicies.Count -eq 1 -and $branchPolicies[0].name -eq "main" -and $branchPolicies[0].type -eq "branch") "only main may deploy to staging"

$expectedVariables = @{
  AWS_ACCOUNT_ID = "816954358294"
  AWS_REGION = "ap-northeast-2"
  AWS_ROLE_ARN = "arn:aws:iam::816954358294:role/logitrack-staging-image-publisher"
  AWS_RUNTIME_INSTANCE_ID = "i-07de6c372fc44e964"
  AWS_RUNTIME_ROLE_ARN = "arn:aws:iam::816954358294:role/logitrack-staging-runtime-deployer"
  ECR_REPOSITORY_PREFIX = "logitrack"
}
$variablesResult = Invoke-GitHubGet "/environments/$Environment/variables?per_page=100"
$variables = @($variablesResult.variables)
Assert-True ($variables.Count -eq $expectedVariables.Count) "staging variable set drifted"
foreach ($variable in $variables) {
  Assert-True ($expectedVariables.ContainsKey($variable.name) -and $expectedVariables[$variable.name] -eq $variable.value) "staging variable drifted: $($variable.name)"
}

$environmentSecrets = Invoke-GitHubGet "/environments/$Environment/secrets?per_page=100"
$repositorySecrets = Invoke-GitHubGet "/actions/secrets?per_page=100"
Assert-True ($environmentSecrets.total_count -eq 0) "staging environment must remain OIDC-only"
$repositorySecretNames = @($repositorySecrets.secrets | ForEach-Object { $_.name } | Sort-Object)
$expectedRepositorySecretNames = @("DOCKERHUB_TOKEN")
Assert-True ($repositorySecrets.total_count -eq 1 -and ($repositorySecretNames -join ",") -eq ($expectedRepositorySecretNames -join ",")) "repository Actions secret set drifted"

$dockerHubWorkflow = Invoke-GitHubGet "/actions/workflows/publish-dockerhub-images.yml"
Assert-True ($dockerHubWorkflow.state -eq "active" -and $dockerHubWorkflow.path -eq ".github/workflows/publish-dockerhub-images.yml") "Docker Hub publication workflow is not active"
$mainCommit = Invoke-GitHubGet "/commits/main"
$ciRuns = Invoke-GitHubGet "/actions/workflows/ci.yml/runs?branch=main&event=push&status=success&per_page=1"
$latestCiRun = @($ciRuns.workflow_runs | Where-Object { $null -ne $_ })
Assert-True ($latestCiRun.Count -eq 1 -and $latestCiRun[0].event -eq "push") "CI has no successful main push run"
Assert-True ($latestCiRun[0].head_sha -eq $mainCommit.sha) "latest main commit has not completed CI and Docker Hub publication"

$dockerHubServices = @("api", "analytics", "simulator", "web", "otel-collector")
foreach ($service in $dockerHubServices) {
  $dockerHubRepository = Invoke-RestMethod -Method Get -Uri "https://hub.docker.com/v2/repositories/$Owner/logitrack-$service/"
  Assert-True (-not $dockerHubRepository.is_private -and $dockerHubRepository.namespace -eq $Owner -and $dockerHubRepository.name -eq "logitrack-$service") "Docker Hub repository identity or visibility drifted: $service"
  $dockerHubTag = Invoke-RestMethod -Method Get -Uri "https://hub.docker.com/v2/repositories/$Owner/logitrack-$service/tags/$($mainCommit.sha)"
  Assert-True ($dockerHubTag.name -eq $mainCommit.sha -and $dockerHubTag.digest -match '^sha256:[0-9a-f]{64}$') "Docker Hub immutable tag or digest drifted: $service"
  $linuxAmd64Images = @($dockerHubTag.images | Where-Object { $_.os -eq "linux" -and $_.architecture -eq "amd64" })
  Assert-True ($linuxAmd64Images.Count -eq 1) "Docker Hub image platform drifted: $service"
}

Write-Output "PASS: GitHub main, staging CD, Docker Hub CD, private reporting, dependency, secret, and CodeQL boundaries are intact"
