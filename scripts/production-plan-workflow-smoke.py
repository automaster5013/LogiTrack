from pathlib import Path

root = Path(__file__).resolve().parents[1]
workflow = (root / ".github/workflows/production-plan.yml").read_text(encoding="utf-8")

required = (
    "workflow_dispatch:",
    "options: [alerting, audit, certificates, data, compute, edge]",
    "environment: production-plan",
    "cancel-in-progress: false",
    "id-token: write",
    "attestations: write",
    "ref: ${{ inputs.revision }}",
    'test "$(git rev-parse origin/main)" = "$REQUESTED_REVISION"',
    "PRODUCTION_TERRAFORM_PLAN_ROLE_ARN",
    "PRODUCTION_TFVARS_BY_ROOT",
    "PRODUCTION_PLAN_GPG_PUBLIC_KEY_B64",
    "PRODUCTION_PLAN_GPG_FINGERPRINT",
    "-detailed-exitcode",
    "production-plan-evidence.py",
    "actions/attest@",
    "retention-days: 7",
    "Remove plaintext plan material",
)
for contract in required:
    if contract not in workflow:
        raise AssertionError(f"production plan workflow is missing: {contract}")

for forbidden in (
    "terraform apply",
    "production.tfplan\n          ",
    "cancel-in-progress: true",
    "pull_request:",
    "push:",
):
    if forbidden in workflow:
        raise AssertionError(f"production plan workflow contains forbidden behavior: {forbidden}")

if workflow.count("persist-credentials: false") != 1:
    raise AssertionError("checkout credentials must not persist")
job_env = workflow.split("    env:\n", 1)[1].split("    steps:\n", 1)[0]
if "PRODUCTION_TFVARS_BY_ROOT" in job_env:
    raise AssertionError("sensitive tfvars must be scoped to the preparation step, not the whole job")
if "tfplan.gpg" not in workflow or "production.tfplan\"\n" not in workflow:
    raise AssertionError("only the encrypted plan may be uploaded and plaintext must be removed")

print("PASS: production plan workflow is approval-gated, current-main-bound, non-applying, encrypted, and attested")
