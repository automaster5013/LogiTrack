from pathlib import Path


source = Path("scripts/github-cd-boundary-audit.ps1").read_text(encoding="utf-8")
required = (
    "Invoke-RestMethod -Method Get",
    "/actions/permissions",
    "sha_pinning_required",
    "default_workflow_permissions",
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
print("PASS: GitHub CD audit covers approval, branch, variables, secrets, and action permissions")
