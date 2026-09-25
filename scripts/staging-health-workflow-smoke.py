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
    "default-src 'self'",
    "connect-src 'self' https://tiles.openfreemap.org",
    "content-security-policy: .*localhost",
    "frame-src 'none'",
    "img-src 'self' data: blob: https://tiles.openfreemap.org",
    "worker-src 'self' blob:",
    "x-content-type-options",
    "x-frame-options",
    "cross-origin-opener-policy: same-origin",
    "cross-origin-resource-policy: same-origin",
    "origin-agent-cluster: \\?1",
    "x-permitted-cross-domain-policies: none",
    "server|via|x-powered-by|x-nextjs-[^:]*",
    "SECURE OPERATOR ACCESS",
    "운영자 로그인",
    "token_exchange_failed",
    "인증 서버가 로그인을 완료하지 못했습니다",
    "다시 로그인하기",
    "authentication error pages must not mutate authentication cookies",
    "unknown authentication errors must not be rendered as trusted operator guidance",
    '"https://$TARGET_HOST/"',
    "LIVE LOGISTICS INTELLIGENCE",
    "물류의 모든 순간을",
    '"https://$TARGET_HOST/showcase"',
    "SEOUL CONTROL TOWER",
    "주문과 운송의 연결",
    "재고와 현장의 동기화",
    "문제를 놓치지 않는 운영",
    "logitrack-showcase-css-paths",
    "while read -r showcase_css",
    "height:100dvh",
    "grid-template-rows:64px minmax(0,1fr) auto 38px",
    '"https://$TARGET_HOST/console"',
    "returnTo=%2Fconsole",
    "forged_console_headers",
    "forged_token",
    "4102444800",
    '"https://$TARGET_HOST/auth/login"',
    "__Host-lt_oauth_state __Host-lt_oidc_nonce __Host-lt_pkce_verifier",
    "code_challenge_method=S256",
    "authorization_location",
    "redirect_state",
    "cookie_state",
    "redirect_nonce",
    "cookie_nonce",
    "pkce_verifier",
    "expected_challenge",
    '"https://$TARGET_HOST/auth/callback"',
    "invalid_callback_status",
    "invalid_oauth_response",
    "invalid callback must not create or mutate the access token cookie",
    "/api/runtime-version",
    "jq -e",
    "cache-control: .*no-store",
    "cross_origin_logout_status",
    "Origin: https://attacker.invalid",
    'cross_origin_logout_rejected',
    "rejected cross-origin logout must not mutate authentication cookies",
    "same_origin_logout_status",
    "logout_location",
    "logout_uri=https%3A%2F%2Fwww.logitrack.kr%2Flogin",
    'Origin: https://$TARGET_HOST',
    "clear-site-data",
    "https://auth\\.logitrack\\.kr/logout\\?",
    "__Host-lt_access_token lt_access_token __Host-lt_oauth_state __Host-lt_oidc_nonce __Host-lt_pkce_verifier",
    "cross_origin_bff_status",
    "for method in POST DELETE",
    "cross_origin_request_rejected",
    "same_origin_bff_status",
    "authentication_required",
    "anonymous_read_status",
    "rejected cross-origin proxy requests must not mutate authentication cookies",
    "anonymous proxy rejection must not mutate authentication cookies",
    "anonymous proxy reads must not mutate authentication cookies",
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
print("PASS: scheduled staging health verifies showcase layout, public TLS, auth boundaries, and private ports without credentials")
