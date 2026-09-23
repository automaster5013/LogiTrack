from pathlib import Path


source = Path("scripts/github-cd-boundary-audit.ps1").read_text(encoding="utf-8")
required = (
    "Invoke-RestMethod -Method Get",
    "/actions/permissions",
    "sha_pinning_required",
    "default_workflow_permissions",
    "/branches/main/protection",
    "allow_squash_merge",
    "delete_branch_on_merge",
    "secret_scanning.status",
    "secret_scanning_push_protection.status",
    "dependabot_security_updates.status",
    'Get-GitHubStatus "/vulnerability-alerts"',
    'Get-GitHubStatus "/automated-security-fixes"',
    'Invoke-GitHubGet "/private-vulnerability-reporting"',
    "privateVulnerabilityReporting.enabled",
    "/dependabot/alerts?state=open",
    "/secret-scanning/alerts?state=open",
    "/code-scanning/default-setup",
    'query_suite -eq "extended"',
    'schedule -eq "weekly"',
    "/code-scanning/alerts?state=open",
    "security_severity_level",
    "required_status_checks.strict",
    "Dependency vulnerability review",
    "required_pull_request_reviews",
    "required_approving_review_count",
    "dismiss_stale_reviews",
    "enforce_admins.enabled",
    "required_linear_history.enabled",
    "allow_force_pushes.enabled",
    "allow_deletions.enabled",
    "required_reviewers",
    "deployment-branch-policies",
    'name -eq "main"',
    "AWS_RUNTIME_ROLE_ARN",
    "ECR_REPOSITORY_PREFIX",
    "/environments/$Environment/secrets",
    "/actions/secrets",
)
missing = [control for control in required if control not in source]
if missing:
    raise SystemExit("ERROR: GitHub CD audit is missing controls: " + ", ".join(missing))
for mutation in ("-Method Post", "-Method Put", "-Method Patch", "-Method Delete"):
    if mutation in source:
        raise SystemExit(f"ERROR: GitHub CD audit must remain read-only: {mutation}")
print("PASS: GitHub audit covers PR protection, private reporting, dependency, secret, CodeQL, merge, deployment, and action boundaries")
