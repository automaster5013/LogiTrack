from pathlib import Path


source = Path("web/app/backend/[...path]/route.ts").read_text(encoding="utf-8")
page_proxy = Path("web/proxy.ts").read_text(encoding="utf-8")
next_config = Path("web/next.config.ts").read_text(encoding="utf-8")
required = (
    "const maxRequestBodyBytes = 1024 * 1024",
    'request.headers.get("content-length")',
    "request.body.getReader()",
    "total > maxRequestBodyBytes",
    "await reader.cancel()",
    'jsonError("request_body_too_large", 413)',
    "AbortSignal.timeout(upstreamTimeoutMs)",
    'redirect: "manual"',
    'cache: "no-store"',
    'jsonError("upstream_unavailable", 502)',
    'new Headers({ Authorization: `Bearer ${token}` })',
    'request.method !== "GET" && !isSameOriginMutation(request)',
    'jsonError("cross_origin_request_rejected", 403)',
    'request.headers.get("origin")',
    "new URL(origin).origin === applicationOrigin(request.nextUrl.origin)",
    'request.headers.get("sec-fetch-site")',
    'fetchSite === "same-origin"',
    'fetchSite === "none"',
)
missing = [boundary for boundary in required if boundary not in source]
if missing:
    raise SystemExit("ERROR: web proxy is missing boundaries: " + ", ".join(missing))
if 'request.headers.get("host")' in source:
    raise SystemExit("ERROR: web proxy must not forward the client Host header")
if "backend/" not in page_proxy:
    raise SystemExit("ERROR: page authentication must not intercept the BFF JSON security contract")

csp_boundaries = (
    'sourceOrigin(process.env.NEXT_PUBLIC_API_URL||"http://localhost:8080","NEXT_PUBLIC_API_URL",true)',
    'sourceOrigin(process.env.NEXT_PUBLIC_MAP_STYLE_URL||"https://tiles.openfreemap.org/styles/liberty","NEXT_PUBLIC_MAP_STYLE_URL")',
    'if(allowRelative&&value.startsWith("/")&&!value.startsWith("//"))return undefined',
    "url.username||url.password",
    "`connect-src ${connectSources}`",
    "`img-src 'self' data: blob: ${mapOrigin}`",
)
missing = [boundary for boundary in csp_boundaries if boundary not in next_config]
if missing:
    raise SystemExit("ERROR: web CSP does not scope API and map origins at build time: " + ", ".join(missing))
print("PASS: authenticated web proxy enforces mutation origins and bounds bodies, upstream waits, redirects, and forwarded headers")
