from pathlib import Path
import yaml

source = Path(".github/workflows/aws-boundary-audit.yml").read_text(encoding="utf-8")
workflow = yaml.safe_load(source)
trigger = workflow.get(True, workflow.get("on", {}))
job = workflow.get("jobs", {}).get("audit", {})
errors = []
if set(trigger) != {"workflow_dispatch", "schedule"}: errors.append("audit triggers drifted")
if trigger.get("schedule") != [{"cron": "23 20 * * *"}]: errors.append("audit cadence drifted")
if workflow.get("permissions") != {"contents": "read", "id-token": "write"}: errors.append("audit permissions drifted")
if "environment" in job: errors.append("read-only audit must not require a deployment environment")
if job.get("runs-on") != "ubuntu-24.04" or job.get("timeout-minutes") != 10: errors.append("audit runner bounds drifted")
for boundary in ("actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1", "persist-credentials: false", "aws-actions/configure-aws-credentials@e1253824e5c10ff9df46874f81ed3ec929e19cfd", "logitrack-staging-boundary-auditor", 'allowed-account-ids: "816954358294"', "unset-current-credentials: true", "translate-env-variables: false", 'aws-runtime-audit.ps1 -Profile ""', 'aws-auth-audit.ps1 -Profile ""'):
    if boundary not in source: errors.append(f"audit workflow is missing boundary: {boundary}")
if errors: raise SystemExit("\n".join(f"ERROR: {error}" for error in errors))
print("PASS: scheduled AWS boundary audit uses a pinned read-only main-branch OIDC workflow")
