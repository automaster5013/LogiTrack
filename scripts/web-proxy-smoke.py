from pathlib import Path


source = Path("web/app/backend/[...path]/route.ts").read_text(encoding="utf-8")
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
)
missing = [boundary for boundary in required if boundary not in source]
if missing:
    raise SystemExit("ERROR: web proxy is missing boundaries: " + ", ".join(missing))
if 'request.headers.get("host")' in source:
    raise SystemExit("ERROR: web proxy must not forward the client Host header")
print("PASS: authenticated web proxy bounds request bodies, upstream waits, redirects, and forwarded headers")
