from pathlib import Path

import yaml


path = Path(".github/workflows/staging-health.yml")
source = path.read_text(encoding="utf-8")
workflow = yaml.safe_load(source)
trigger = workflow.get(True, workflow.get("on", {}))
job = workflow.get("jobs", {}).get("health", {})

errors = []
if set(trigger) != {"workflow_dispatch", "schedule"}:
    errors.append("health workflow must only support manual and scheduled execution")
if trigger.get("schedule") != [{"cron": "17 */6 * * *"}]:
    errors.append("health workflow must run at the reviewed six-hour cadence")
if workflow.get("permissions") != {}:
    errors.append("health workflow must not receive a GitHub token permission")
if job.get("runs-on") != "ubuntu-24.04" or job.get("timeout-minutes") != 5:
    errors.append("health runner and timeout must remain pinned and bounded")
if any("uses" in step for step in job.get("steps", [])):
    errors.append("health workflow must not depend on third-party actions")
for boundary in (
    "--proto '=https'",
    "--tlsv1.2",
    "strict-transport-security",
    "content-security-policy",
    "base-uri 'self'; form-action 'self'; frame-ancestors 'none'; object-src 'none'",
    "x-content-type-options",
    "x-frame-options",
    "x-powered-by:",
    "SECURE OPERATOR ACCESS",
    "운영자 로그인",
    "/api/runtime-version",
    "jq -e",
    "cache-control: .*no-store",
    "openssl x509 -checkend 1209600",
    "for port in 3000 5432 6379 8080 8090 29092",
):
    if boundary not in source:
        errors.append(f"health workflow is missing boundary: {boundary}")

if errors:
    raise SystemExit("\n".join(f"ERROR: {error}" for error in errors))
print("PASS: scheduled staging health verifies public TLS and private port boundaries without credentials")
