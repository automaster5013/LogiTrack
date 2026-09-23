from pathlib import Path

import yaml


path = Path(".github/workflows/staging-health.yml")
source = path.read_text(encoding="utf-8")
caddy = Path("deploy/staging/Caddyfile").read_text(encoding="utf-8")
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
if job.get("env") != {"AUTH_HOST": "auth.logitrack.kr", "TARGET_HOST": "www.logitrack.kr"}:
    errors.append("health workflow must pin the reviewed application and authentication hosts")
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
    "server|via|x-powered-by|x-nextjs-[^:]*",
    "SECURE OPERATOR ACCESS",
    "운영자 로그인",
    "/api/runtime-version",
    "jq -e",
    "cache-control: .*no-store",
    "cross_origin_logout_status",
    "Origin: https://attacker.invalid",
    'cross_origin_logout_rejected',
    "rejected cross-origin logout must not mutate authentication cookies",
    "same_origin_logout_status",
    'Origin: https://$TARGET_HOST',
    "clear-site-data",
    "https://auth\\.logitrack\\.kr/logout\\?",
    "lt_access_token lt_oauth_state lt_oidc_nonce lt_pkce_verifier",
    "cross_origin_bff_status",
    "for method in POST DELETE",
    "cross_origin_request_rejected",
    "same_origin_bff_status",
    "authentication_required",
    "/backend/api/deliveries",
    'getent ahostsv4 "$AUTH_HOST"',
    '"https://$AUTH_HOST/oauth2/authorize"',
    "https://auth\\.logitrack\\.kr/error\\?error=",
    'servername "$AUTH_HOST"',
    "openssl x509 -checkend 1209600",
    "for port in 3000 5432 6379 8080 8090 29092",
):
    if boundary not in source:
        errors.append(f"health workflow is missing boundary: {boundary}")

if errors:
    raise SystemExit("\n".join(f"ERROR: {error}" for error in errors))
for header in ("-Server", "-Via", "-X-Powered-By", "-X-Nextjs-*"):
    if header not in caddy:
        raise SystemExit(f"ERROR: staging proxy does not suppress identity header: {header}")
print("PASS: scheduled staging health verifies public TLS, auth mutation origins, and private port boundaries without credentials")
