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
$requestTimeoutSeconds = 30
. (Join-Path $PSScriptRoot "github-pagination.ps1")

function Invoke-GitHubGet {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Path)
  return Invoke-RestMethod -Method Get -Uri "$baseUri$Path" -Headers $headers -MaximumRedirection 0 -TimeoutSec $requestTimeoutSeconds
}

function Get-GitHubStatus {
  param([Parameter(Mandatory)][string]$Path)
  $response = Invoke-WebRequest -Method Get -Uri "$baseUri$Path" -Headers $headers -MaximumRedirection 0 -TimeoutSec $requestTimeoutSeconds
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
$dependabotAlerts = @(Invoke-GitHubGetAll -Path "/dependabot/alerts?state=open" -BaseUri $baseUri -Headers $headers -TimeoutSeconds $requestTimeoutSeconds)
$highRiskAlerts = @($dependabotAlerts | Where-Object { $_.security_advisory.severity -in @("critical", "high") })
Assert-True ($highRiskAlerts.Count -eq 0) "open critical or high Dependabot alerts require remediation"
$secretAlerts = @(Invoke-GitHubGetAll -Path "/secret-scanning/alerts?state=open" -BaseUri $baseUri -Headers $headers -TimeoutSeconds $requestTimeoutSeconds)
Assert-True ($secretAlerts.Count -eq 0) "open secret scanning alerts require remediation"
$codeScanning = Invoke-GitHubGet "/code-scanning/default-setup"
$codeLanguages = @($codeScanning.languages | Sort-Object)
$expectedCodeLanguages = @("actions", "java-kotlin", "javascript", "javascript-typescript", "python", "typescript") | Sort-Object
Assert-True ($codeScanning.state -eq "configured" -and $codeScanning.query_suite -eq "extended" -and $codeScanning.threat_model -eq "remote") "CodeQL default setup drifted"
Assert-True ($codeScanning.runner_type -eq "standard" -and $codeScanning.schedule -eq "weekly" -and ($codeLanguages -join ",") -eq ($expectedCodeLanguages -join ",")) "CodeQL language, runner, or schedule drifted"
$codeAlerts = @(Invoke-GitHubGetAll -Path "/code-scanning/alerts?state=open" -BaseUri $baseUri -Headers $headers -TimeoutSeconds $requestTimeoutSeconds)
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
$provenanceAuditWorkflow = Invoke-GitHubGet "/actions/workflows/dockerhub-provenance-audit.yml"
Assert-True ($provenanceAuditWorkflow.state -eq "active" -and $provenanceAuditWorkflow.path -eq ".github/workflows/dockerhub-provenance-audit.yml") "Docker Hub provenance audit workflow is not active"
$mainCommit = Invoke-GitHubGet "/commits/main"
$mainCommittedAt = [DateTimeOffset]::Parse([string]$mainCommit.commit.committer.date)
$ciRuns = Invoke-GitHubGet "/actions/workflows/ci.yml/runs?branch=main&event=push&per_page=1"
$latestCiRun = @($ciRuns.workflow_runs | Where-Object { $null -ne $_ })
Assert-True ($latestCiRun.Count -eq 1 -and $latestCiRun[0].event -eq "push") "CI has no main push run"
Assert-True ($latestCiRun[0].head_sha -eq $mainCommit.sha -and $latestCiRun[0].status -eq "completed" -and $latestCiRun[0].conclusion -eq "success") "latest main CI and Docker Hub publication has not completed successfully"

$provenanceAuditRuns = Invoke-GitHubGet "/actions/workflows/dockerhub-provenance-audit.yml/runs?branch=main&per_page=1"
$latestProvenanceAudit = @($provenanceAuditRuns.workflow_runs | Where-Object { $null -ne $_ })
Assert-True ($latestProvenanceAudit.Count -eq 1) "Docker Hub provenance audit has no main run"
$auditRun = $latestProvenanceAudit[0]
Assert-True ($auditRun.head_sha -eq $mainCommit.sha -and $auditRun.head_branch -eq "main" -and $auditRun.status -eq "completed" -and $auditRun.conclusion -eq "success") "latest main Docker Hub provenance audit has not completed successfully"
Assert-True ($auditRun.event -in @("schedule", "workflow_dispatch") -and $auditRun.run_attempt -ge 1) "Docker Hub provenance audit run identity drifted"
$auditCreatedAt = [DateTimeOffset]::Parse([string]$auditRun.created_at)
$auditAge = [DateTimeOffset]::UtcNow - $auditCreatedAt
Assert-True ($auditAge.TotalMinutes -ge -5 -and $auditAge.TotalHours -le 26) "Docker Hub provenance audit is stale"

$provenanceArtifacts = Invoke-GitHubGet "/actions/runs/$($auditRun.id)/artifacts?per_page=10"
$auditArtifacts = @($provenanceArtifacts.artifacts)
Assert-True ($provenanceArtifacts.total_count -eq 1 -and $auditArtifacts.Count -eq 1) "Docker Hub provenance audit evidence artifact count drifted"
$auditArtifact = $auditArtifacts[0]
$expectedAuditArtifactName = "dockerhub-provenance-audit-$($mainCommit.sha)-$($auditRun.run_attempt)"
Assert-True ($auditArtifact.name -eq $expectedAuditArtifactName -and -not $auditArtifact.expired -and $auditArtifact.size_in_bytes -gt 0 -and $auditArtifact.size_in_bytes -le 1MB) "Docker Hub provenance audit evidence identity, availability, or archive size drifted"
Assert-True ($auditArtifact.digest -match '^sha256:[0-9a-f]{64}$') "Docker Hub provenance audit evidence digest is invalid"
Assert-True ($auditArtifact.workflow_run.id -eq $auditRun.id -and $auditArtifact.workflow_run.repository_id -eq $repositoryInfo.id -and $auditArtifact.workflow_run.head_sha -eq $mainCommit.sha -and $auditArtifact.workflow_run.head_branch -eq "main") "Docker Hub provenance audit evidence run binding drifted"
$artifactCreatedAt = [DateTimeOffset]::Parse([string]$auditArtifact.created_at)
$artifactExpiresAt = [DateTimeOffset]::Parse([string]$auditArtifact.expires_at)
$artifactRetention = $artifactExpiresAt - $artifactCreatedAt
Assert-True ($artifactRetention.TotalDays -ge 29.9 -and $artifactRetention.TotalDays -le 30.1) "Docker Hub provenance audit evidence retention drifted"
$expectedArtifactUrl = "https://api.github.com/repos/$Owner/$Repository/actions/artifacts/$($auditArtifact.id)"
Assert-True ($auditArtifact.url -eq $expectedArtifactUrl -and $auditArtifact.archive_download_url -eq "$expectedArtifactUrl/zip") "Docker Hub provenance audit evidence URL escaped the repository"

$dockerHubServices = @("api", "analytics", "simulator", "web", "otel-collector")
$auditedDockerHubDigests = @{}
$expectedEvidenceFiles = @($dockerHubServices | ForEach-Object { "logitrack-$_.provenance.json"; "logitrack-$_.tag.json" } | Sort-Object)
$expectedArchiveEntries = @($expectedEvidenceFiles + "SHA256SUMS" | Sort-Object)
$auditTempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "logitrack-provenance-audit-$([guid]::NewGuid().ToString('N'))"
try {
  New-Item -ItemType Directory -Path $auditTempRoot | Out-Null
  $auditArchive = Join-Path $auditTempRoot "evidence.zip"
  $auditEvidenceRoot = Join-Path $auditTempRoot "evidence"
  Invoke-WebRequest -Method Get -Uri $auditArtifact.archive_download_url -Headers $headers -OutFile $auditArchive -TimeoutSec $requestTimeoutSeconds
  $downloadedArchiveSize = (Get-Item -LiteralPath $auditArchive).Length
  Assert-True ($downloadedArchiveSize -eq $auditArtifact.size_in_bytes -and $downloadedArchiveSize -le 1MB) "downloaded Docker Hub provenance audit archive size does not match GitHub"
  $downloadedArchiveDigest = "sha256:$((Get-FileHash -LiteralPath $auditArchive -Algorithm SHA256).Hash.ToLowerInvariant())"
  Assert-True ($downloadedArchiveDigest -eq $auditArtifact.digest) "downloaded Docker Hub provenance audit archive digest does not match GitHub"
  $archive = [System.IO.Compression.ZipFile]::OpenRead($auditArchive)
  try {
    $archiveEntries = @($archive.Entries)
    $archiveEntryNames = @($archiveEntries.FullName | Sort-Object)
    Assert-True ($archiveEntries.Count -eq 11 -and ($archiveEntryNames -join ",") -eq ($expectedArchiveEntries -join ",")) "Docker Hub provenance audit ZIP entry set drifted"
    Assert-True (@($archiveEntryNames | Select-Object -Unique).Count -eq 11) "Docker Hub provenance audit ZIP contains duplicate entries"
    $totalExpandedBytes = 0L
    foreach ($entry in $archiveEntries) {
      Assert-True ($entry.FullName -eq $entry.Name -and -not [string]::IsNullOrWhiteSpace($entry.Name)) "Docker Hub provenance audit ZIP contains a nested or unsafe path"
      Assert-True ($entry.Length -gt 0 -and $entry.Length -le 2MB -and $entry.CompressedLength -gt 0 -and $entry.CompressedLength -le 1MB) "Docker Hub provenance audit ZIP entry size is invalid: $($entry.FullName)"
      $totalExpandedBytes += $entry.Length
    }
    Assert-True ($totalExpandedBytes -le 10MB) "Docker Hub provenance audit ZIP expanded size exceeds the limit"
  } finally {
    $archive.Dispose()
  }
  Expand-Archive -LiteralPath $auditArchive -DestinationPath $auditEvidenceRoot

  $jsonFiles = @(Get-ChildItem -LiteralPath $auditEvidenceRoot -File -Filter "*.json")
  $actualEvidenceFiles = @($jsonFiles.Name | Sort-Object)
  Assert-True ($jsonFiles.Count -eq 10 -and ($actualEvidenceFiles -join ",") -eq ($expectedEvidenceFiles -join ",")) "Docker Hub provenance audit evidence file set drifted"
  $checksumPath = Join-Path $auditEvidenceRoot "SHA256SUMS"
  Assert-True (Test-Path -LiteralPath $checksumPath -PathType Leaf) "Docker Hub provenance audit evidence checksum list is missing"
  $checksumLines = @(Get-Content -LiteralPath $checksumPath)
  Assert-True ($checksumLines.Count -eq 10) "Docker Hub provenance audit checksum count drifted"
  $checksumFiles = @()
  foreach ($line in $checksumLines) {
    Assert-True ($line -match '^([0-9a-f]{64})  \./(logitrack-(api|analytics|simulator|web|otel-collector)\.(provenance|tag)\.json)$') "Docker Hub provenance audit checksum entry is invalid"
    $expectedHash = $matches[1]
    $filename = $matches[2]
    $checksumFiles += $filename
    $evidencePath = Join-Path $auditEvidenceRoot $filename
    Assert-True (Test-Path -LiteralPath $evidencePath -PathType Leaf) "Docker Hub provenance audit checksum references a missing file"
    $actualHash = (Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-True ($actualHash -eq $expectedHash) "Docker Hub provenance audit evidence content hash does not match: $filename"
  }
  Assert-True ((@($checksumFiles | Sort-Object) -join ",") -eq ($expectedEvidenceFiles -join ",")) "Docker Hub provenance audit checksum file set drifted"

  foreach ($service in $dockerHubServices) {
    $tagEvidence = Get-Content -Raw -LiteralPath (Join-Path $auditEvidenceRoot "logitrack-$service.tag.json") | ConvertFrom-Json
    Assert-True ($tagEvidence.name -eq $mainCommit.sha -and $tagEvidence.digest -match '^sha256:[0-9a-f]{64}$') "Docker Hub provenance tag evidence is invalid: $service"
    $auditedDockerHubDigests[$service] = [string]$tagEvidence.digest
    $evidencePlatforms = @($tagEvidence.images | Where-Object { $_.os -eq "linux" -and $_.architecture -eq "amd64" })
    Assert-True (@($tagEvidence.images).Count -eq 1 -and $evidencePlatforms.Count -eq 1) "Docker Hub provenance tag evidence platform set drifted: $service"
    $verificationEvidence = @(Get-Content -Raw -LiteralPath (Join-Path $auditEvidenceRoot "logitrack-$service.provenance.json") | ConvertFrom-Json)
    Assert-True ($verificationEvidence.Count -eq 1) "Docker Hub provenance verification evidence must contain exactly one attestation: $service"
    $verifiedTimestamps = @($verificationEvidence[0].verificationResult.verifiedTimestamps)
    Assert-True ($verifiedTimestamps.Count -eq 1 -and $verifiedTimestamps[0].type -eq "Tlog" -and $verifiedTimestamps[0].uri -eq "https://rekor.sigstore.dev") "Docker Hub provenance transparency log evidence drifted: $service"
    $transparencyTimestamp = [DateTimeOffset]::Parse([string]$verifiedTimestamps[0].timestamp)
    Assert-True ($transparencyTimestamp -ge $mainCommittedAt.AddMinutes(-5) -and $transparencyTimestamp -le $auditCreatedAt.AddMinutes(5)) "Docker Hub provenance transparency timestamp is outside the trusted release window: $service"
    $expectedSubject = "docker.io/$Owner/logitrack-$service"
    $expectedSubjectDigest = ([string]$tagEvidence.digest).Substring(7)
    $expectedRepositoryUrl = "https://github.com/$Owner/$Repository"
    $expectedSigner = "$expectedRepositoryUrl/.github/workflows/publish-dockerhub-images.yml@refs/heads/main"
    $expectedBuildConfig = "$expectedRepositoryUrl/.github/workflows/ci.yml@refs/heads/main"
    $expectedDependency = "git+$expectedRepositoryUrl@refs/heads/main"
    $matchingStatements = @($verificationEvidence | Where-Object {
      $result = $_.verificationResult
      $certificate = $result.signature.certificate
      $statement = $result.statement
      $buildDefinition = $statement.predicate.buildDefinition
      $workflow = $buildDefinition.externalParameters.workflow
      $github = $buildDefinition.internalParameters.github
      $dependencies = @($buildDefinition.resolvedDependencies)
      $invocationId = [string]$statement.predicate.runDetails.metadata.invocationId
      $certificate.certificateIssuer -eq "CN=sigstore-intermediate,O=sigstore.dev" -and
      $certificate.issuer -eq "https://token.actions.githubusercontent.com" -and
      $certificate.subjectAlternativeName -eq $expectedSigner -and
      $certificate.githubWorkflowName -eq "CI" -and
      $certificate.githubWorkflowTrigger -eq "push" -and
      $certificate.githubWorkflowRepository -eq "$Owner/$Repository" -and
      $certificate.githubWorkflowRef -eq "refs/heads/main" -and
      $certificate.githubWorkflowSHA -eq $mainCommit.sha -and
      $certificate.buildSignerURI -eq $expectedSigner -and
      $certificate.buildSignerDigest -eq $mainCommit.sha -and
      $certificate.runnerEnvironment -eq "github-hosted" -and
      $certificate.sourceRepositoryURI -eq $expectedRepositoryUrl -and
      $certificate.sourceRepositoryDigest -eq $mainCommit.sha -and
      $certificate.sourceRepositoryRef -eq "refs/heads/main" -and
      $certificate.sourceRepositoryIdentifier -eq [string]$repositoryInfo.id -and
      $certificate.sourceRepositoryOwnerURI -eq "https://github.com/$Owner" -and
      $certificate.sourceRepositoryOwnerIdentifier -eq [string]$repositoryInfo.owner.id -and
      $certificate.buildConfigURI -eq $expectedBuildConfig -and
      $certificate.buildConfigDigest -eq $mainCommit.sha -and
      $certificate.buildTrigger -eq "push" -and
      $certificate.sourceRepositoryVisibilityAtSigning -eq "public" -and
      $certificate.runInvocationURI -eq $invocationId -and
      $invocationId -match "^https://github\.com/$Owner/$Repository/actions/runs/[1-9][0-9]*/attempts/[1-9][0-9]*$" -and
      $result.verifiedIdentity.runnerEnvironment -eq "github-hosted" -and
      $statement.predicateType -eq "https://slsa.dev/provenance/v1" -and
      $buildDefinition.buildType -eq "https://actions.github.io/buildtypes/workflow/v1" -and
      $workflow.repository -eq $expectedRepositoryUrl -and $workflow.ref -eq "refs/heads/main" -and $workflow.path -eq ".github/workflows/ci.yml" -and
      $github.event_name -eq "push" -and $github.repository_id -eq [string]$repositoryInfo.id -and $github.repository_owner_id -eq [string]$repositoryInfo.owner.id -and $github.runner_environment -eq "github-hosted" -and
      $dependencies.Count -eq 1 -and $dependencies[0].uri -eq $expectedDependency -and $dependencies[0].digest.gitCommit -eq $mainCommit.sha -and
      $statement.predicate.runDetails.builder.id -eq $expectedSigner -and
      @($statement.subject | Where-Object { $_.name -eq $expectedSubject -and $_.digest.sha256 -eq $expectedSubjectDigest }).Count -eq 1
    })
    Assert-True ($matchingStatements.Count -eq 1) "Docker Hub provenance verification evidence identity, build source, or subject does not match: $service"
  }
} finally {
  if (Test-Path -LiteralPath $auditTempRoot) { Remove-Item -LiteralPath $auditTempRoot -Recurse -Force }
}

foreach ($service in $dockerHubServices) {
  $dockerHubRepository = Invoke-RestMethod -Method Get -Uri "https://hub.docker.com/v2/repositories/$Owner/logitrack-$service/" -MaximumRedirection 0 -TimeoutSec $requestTimeoutSeconds
  Assert-True (-not $dockerHubRepository.is_private -and $dockerHubRepository.namespace -eq $Owner -and $dockerHubRepository.name -eq "logitrack-$service") "Docker Hub repository identity or visibility drifted: $service"
  $dockerHubTag = Invoke-RestMethod -Method Get -Uri "https://hub.docker.com/v2/repositories/$Owner/logitrack-$service/tags/$($mainCommit.sha)" -MaximumRedirection 0 -TimeoutSec $requestTimeoutSeconds
  Assert-True ($dockerHubTag.name -eq $mainCommit.sha -and $dockerHubTag.digest -match '^sha256:[0-9a-f]{64}$') "Docker Hub immutable tag or digest drifted: $service"
  Assert-True ($dockerHubTag.digest -eq $auditedDockerHubDigests[$service]) "Docker Hub live tag digest does not match the sealed provenance audit evidence: $service"
  $linuxAmd64Images = @($dockerHubTag.images | Where-Object { $_.os -eq "linux" -and $_.architecture -eq "amd64" })
  Assert-True (@($dockerHubTag.images).Count -eq 1 -and $linuxAmd64Images.Count -eq 1) "Docker Hub image platform set drifted: $service"
}

$confirmedMainCommit = Invoke-GitHubGet "/commits/main"
Assert-True ($confirmedMainCommit.sha -eq $mainCommit.sha) "main changed while the boundary audit was running; retry against the new head"

Write-Output "PASS: GitHub main, staging CD, Docker Hub CD, provenance evidence, private reporting, dependency, secret, and CodeQL boundaries are intact"
