from pathlib import Path


callback = Path("web/app/auth/callback/route.ts").read_text(encoding="utf-8")
config = Path("web/app/auth/config.ts").read_text(encoding="utf-8")
logout = Path("web/app/auth/logout/route.ts").read_text(encoding="utf-8")

callback_boundaries = (
    "const tokenExchangeTimeoutMs = 10_000",
    "const jwksTimeoutMs = 5_000",
    "const maxTokenResponseBytes = 64 * 1024",
    "const maxAccessTokenCharacters = 32 * 1024",
    "const maxIdTokenCharacters = 16 * 1024",
    "const maxAuthorizationCodeCharacters = 4096",
    "const maxStateCharacters = 256",
    "timingSafeEqual(supplied, expected)",
    "AbortSignal.timeout(tokenExchangeTimeoutMs)",
    'redirect: "error"',
    "timeoutDuration: jwksTimeoutMs",
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
)
missing = [boundary for boundary in logout_boundaries if boundary not in logout]
if missing:
    raise SystemExit("ERROR: OIDC logout is missing boundaries: " + ", ".join(missing))
if 'try{return new URL(callback("OIDC_REDIRECT_URI")).origin}catch{return fallback}' in config:
    raise SystemExit("ERROR: invalid configured redirect origins must fail closed instead of using the fallback origin")

print("PASS: OIDC login, callback, logout, and configuration boundaries are enforced")
