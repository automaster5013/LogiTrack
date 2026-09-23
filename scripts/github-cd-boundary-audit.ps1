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

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "AUDIT FAILED: $Message" }
}

$repositoryInfo = Invoke-GitHubGet ""
Assert-True ($repositoryInfo.id -eq 1376500287 -and $repositoryInfo.owner.id -eq 247691206 -and $repositoryInfo.default_branch -eq "main") "repository identity or default branch drifted"
Assert-True ($repositoryInfo.allow_squash_merge -and -not $repositoryInfo.allow_merge_commit -and -not $repositoryInfo.allow_rebase_merge) "repository must allow squash merge only"
Assert-True ($repositoryInfo.delete_branch_on_merge -and -not $repositoryInfo.allow_auto_merge) "merged branches must be deleted without automatic merging"

$actions = Invoke-GitHubGet "/actions/permissions"
Assert-True ($actions.enabled -and $actions.sha_pinning_required) "Actions must be enabled and require full commit SHA pinning"
$workflowPermissions = Invoke-GitHubGet "/actions/permissions/workflow"
Assert-True ($workflowPermissions.default_workflow_permissions -eq "read" -and -not $workflowPermissions.can_approve_pull_request_reviews) "default workflow token permissions are too broad"

$mainProtection = Invoke-GitHubGet "/branches/main/protection"
$requiredChecks = @($mainProtection.required_status_checks.contexts | Sort-Object)
$expectedChecks = @("API tests and domain coverage", "Production images and supply-chain security", "Python tests and Compose validation", "TypeScript production build") | Sort-Object
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
Assert-True ($environmentSecrets.total_count -eq 0 -and $repositorySecrets.total_count -eq 0) "long-lived GitHub Actions secrets are configured"

Write-Output "PASS: GitHub main and staging CD approval, branch, CI, variable, secret, and action boundaries are intact"
