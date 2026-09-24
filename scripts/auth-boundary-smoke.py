from pathlib import Path


callback = Path("web/app/auth/callback/route.ts").read_text(encoding="utf-8")
config = Path("web/app/auth/config.ts").read_text(encoding="utf-8")
logout = Path("web/app/auth/logout/route.ts").read_text(encoding="utf-8")
login_page = Path("web/app/login/page.tsx").read_text(encoding="utf-8")
proxy = Path("web/proxy.ts").read_text(encoding="utf-8")
access_token = Path("web/app/auth/access-token.ts").read_text(encoding="utf-8")
backend = Path("web/app/backend/[...path]/route.ts").read_text(encoding="utf-8")
api_security = Path("api/src/main/java/io/logitrack/config/SecurityConfig.java").read_text(encoding="utf-8")

callback_boundaries = (
    "const tokenExchangeTimeoutMs = 10_000",
    "const maxTokenResponseBytes = 64 * 1024",
    "const maxAccessTokenCharacters = 32 * 1024",
    "const maxIdTokenCharacters = 16 * 1024",
    "const maxAuthorizationCodeCharacters = 4096",
    "const maxStateCharacters = 256",
    "timingSafeEqual(supplied, expected)",
    "AbortSignal.timeout(tokenExchangeTimeoutMs)",
    'redirect: "error"',
    'response.headers.get("content-length")',
    'response.headers.get("content-type")',
    'mediaType !== "application/json"',
    "response.body.getReader()",
    "total > maxTokenResponseBytes",
    "await reader.cancel()",
    'new TextDecoder("utf-8", { fatal: true })',
    "isTokenResponse(parsed)",
    'typeof token.access_token !== "string"',
    'typeof token.id_token !== "string"',
    'token.token_type.toLowerCase() !== "bearer"',
    "Number.isInteger(token.expires_in)",
    'new URL("/console", applicationOrigin(request.nextUrl.origin))',
    'new URL(`/login?error=${encodeURIComponent(reason)}`, applicationOrigin(request.nextUrl.origin))',
    "verifyAccessToken(token.access_token)",
    'algorithms: ["RS256"]',
    'requiredClaims: ["exp", "iat", "sub", "nonce", "token_use"]',
    'idPayload.token_use !== "id"',
    "idPayload.sub !== accessPayload.sub",
    "accessTokenSecondsRemaining",
    "sessionMaxAge",
)
missing = [boundary for boundary in callback_boundaries if boundary not in callback]
if missing:
    raise SystemExit("ERROR: OIDC callback is missing boundaries: " + ", ".join(missing))

config_boundaries = (
    'process.env.NODE_ENV==="production"&&url.protocol!=="https:"',
    "url.username||url.password||url.search||url.hash",
    'url.protocol!=="https:"&&url.protocol!=="http:"',
    "const configured=process.env.OIDC_REDIRECT_URI?.trim()",
    "if(!configured)return fallback",
    'return new URL(callback("OIDC_REDIRECT_URI")).origin',
)
missing = [boundary for boundary in config_boundaries if boundary not in config]
if missing:
    raise SystemExit("ERROR: OIDC configuration is missing boundaries: " + ", ".join(missing))

logout_boundaries = (
    "isSameOrigin(request)",
    'request.headers.get("origin")',
    "new URL(origin).origin === applicationOrigin(request.nextUrl.origin)",
    'request.headers.get("sec-fetch-site")',
    'fetchSite === "same-origin"',
    'fetchSite === "none"',
    'status: 403, headers: { "Cache-Control": "no-store" }',
    'response.cookies.set(authCookie.access, "", { ...secureCookie(0, "/")',
    "[authCookie.state, authCookie.nonce, authCookie.verifier]",
    'response.headers.set("Cache-Control", "no-store")',
    'response.headers.set("Clear-Site-Data", \'"cache", "storage"\')',
    'new URL("/login", applicationOrigin(request.nextUrl.origin))',
)
missing = [boundary for boundary in logout_boundaries if boundary not in logout]
if missing:
    raise SystemExit("ERROR: OIDC logout is missing boundaries: " + ", ".join(missing))
if 'try{return new URL(callback("OIDC_REDIRECT_URI")).origin}catch{return fallback}' in config:
    raise SystemExit("ERROR: invalid configured redirect origins must fail closed instead of using the fallback origin")

proxy_boundaries = (
    "verifyAccessToken(token)",
    'response.headers.set("Cache-Control","no-store")',
    'response.cookies.set(authCookie.access,""',
    'new URL("/login",applicationOrigin(request.nextUrl.origin))',
)
missing = [boundary for boundary in proxy_boundaries if boundary not in proxy]
if missing:
    raise SystemExit("ERROR: console session verification is missing boundaries: " + ", ".join(missing))
if "atob(" in proxy:
    raise SystemExit("ERROR: console access must not trust an unverified JWT payload")

backend_session_boundaries = (
    'import { verifyAccessToken } from "../../auth/access-token";',
    "await verifyAccessToken(token)",
    'jsonError("invalid_authentication", 401)',
    'response.cookies.set(authCookie.access, "", { ...secureCookie(0, "/"), expires: new Date(0) })',
)
missing = [boundary for boundary in backend_session_boundaries if boundary not in backend]
if missing:
    raise SystemExit("ERROR: BFF session verification is missing boundaries: " + ", ".join(missing))

access_token_boundaries = (
    "createRemoteJWKSet",
    "jwtVerify",
    "const jwksTimeoutMs = 5_000",
    "timeoutDuration: jwksTimeoutMs",
    "accessTokenConfig()",
    'algorithms: ["RS256"]',
    'requiredClaims: ["exp", "iat", "sub", "token_use", "client_id"]',
    'payload.token_use !== "access"',
    "payload.client_id !== clientId",
    "const allowedClockSkewSeconds = 60",
    "Number.isInteger(payload.iat)",
    "payload.iat > now + allowedClockSkewSeconds",
    "payload.exp <= now + 30",
)
missing = [boundary for boundary in access_token_boundaries if boundary not in access_token]
if missing:
    raise SystemExit("ERROR: access token verification is missing boundaries: " + ", ".join(missing))

api_token_boundaries = (
    "jwsAlgorithm(SignatureAlgorithm.RS256)",
    "static final long ALLOWED_CLOCK_SKEW_SECONDS=60",
    '"access".equals(jwt.getClaimAsString("token_use"))',
    'clientId.equals(jwt.getClaimAsString("client_id"))',
    "jwt.getIssuedAt()!=null",
    "now.plusSeconds(ALLOWED_CLOCK_SKEW_SECONDS)",
)
missing = [boundary for boundary in api_token_boundaries if boundary not in api_security]
if missing:
    raise SystemExit("ERROR: API access token verification is missing boundaries: " + ", ".join(missing))

login_error_boundaries = (
    "authenticationErrors:Record<string,string>",
    "invalid_oauth_response",
    "token_exchange_failed",
    "invalid_token_response",
    "authentication_unavailable",
    'className="loginError" role="alert"',
    'errorMessage?"다시 로그인하기"',
)
missing = [boundary for boundary in login_error_boundaries if boundary not in login_page]
if missing:
    raise SystemExit("ERROR: operator login is missing safe error feedback: " + ", ".join(missing))

print("PASS: OIDC login, callback, logout, and configuration boundaries are enforced")
