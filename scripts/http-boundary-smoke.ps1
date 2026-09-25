$ErrorActionPreference = "Stop"
function Headers([string]$url,[string]$origin="") {
  $arguments=@("-sS","-D","-","-o","NUL")
  if($origin){$arguments+=@("-H","Origin: $origin")}
  return (curl.exe @arguments $url) -join "`n"
}
function Preflight([string]$requestHeaders,[string]$origin="http://localhost:3000") {
  return (curl.exe -sS -D - -o NUL -X OPTIONS `
    -H "Origin: $origin" `
    -H "Access-Control-Request-Method: POST" `
    -H "Access-Control-Request-Headers: $requestHeaders" `
    http://localhost:8080/api/deliveries) -join "`n"
}
$api=Headers "http://localhost:8080/api/deliveries" "http://localhost:3000"
$loopbackApi=Headers "http://localhost:8080/api/deliveries" "http://127.0.0.1:3000"
$untrusted=Headers "http://localhost:8080/api/deliveries" "https://untrusted.example"
$web=Headers "http://localhost:3000"
foreach($header in @("X-Permitted-Cross-Domain-Policies: none","X-Content-Type-Options: nosniff","X-Frame-Options: DENY","Referrer-Policy: no-referrer","Permissions-Policy: camera=(), microphone=(), geolocation=()")) {
  if($api -notmatch "(?im)^$([regex]::Escape($header))\s*$") { throw "API security header is missing: $header" }
  if($web -notmatch "(?im)^$([regex]::Escape($header))\s*$") { throw "Web security header is missing: $header" }
}
foreach($header in @("Cross-Origin-Opener-Policy: same-origin","Cross-Origin-Resource-Policy: same-origin","Origin-Agent-Cluster: ?1")) {
  if($web -notmatch "(?im)^$([regex]::Escape($header))\s*$") { throw "Web browsing-context isolation header is missing: $header" }
}
$apiCsp="Content-Security-Policy: base-uri 'self'; form-action 'self'; frame-ancestors 'none'; object-src 'none'"
if($api -notmatch "(?im)^$([regex]::Escape($apiCsp))\s*$") { throw "API content security policy is missing" }
foreach($directive in @("default-src 'self'","connect-src 'self' http://localhost:8080 https://tiles.openfreemap.org","frame-src 'none'","img-src 'self' data: blob: https://tiles.openfreemap.org","media-src 'none'","script-src 'self' 'unsafe-inline'","style-src 'self' 'unsafe-inline'","worker-src 'self' blob:")) {
  if($web -notmatch "(?im)^Content-Security-Policy:.*$([regex]::Escape($directive))") { throw "Web content security policy directive is missing: $directive" }
}
if($api -notmatch "(?im)^Access-Control-Allow-Origin:\s*http://localhost:3000\s*$") { throw "Trusted web origin was not allowed" }
if($loopbackApi -notmatch "(?im)^Access-Control-Allow-Origin:\s*http://127\.0\.0\.1:3000\s*$") { throw "Published loopback web origin was not allowed" }
if($api -notmatch "(?im)^Cache-Control:\s*no-store\s*$") { throw "API responses were not protected from intermediary caching" }
if($untrusted -match "(?im)^Access-Control-Allow-Origin:") { throw "Untrusted origin was allowed" }
$allowedPreflight=Preflight "Authorization, Content-Type, Idempotency-Key, X-Trace-Id, X-Operator, X-Replay-Approval, X-Discard-Approval"
$loopbackPreflight=Preflight "Content-Type" "http://127.0.0.1:3000"
if($loopbackPreflight -notmatch "(?im)^Access-Control-Allow-Origin:\s*http://127\.0\.0\.1:3000\s*$") { throw "Published loopback web origin preflight was not allowed" }
foreach($header in @("Authorization","Content-Type","Idempotency-Key","X-Trace-Id","X-Operator","X-Replay-Approval","X-Discard-Approval")) {
  if($allowedPreflight -notmatch "(?im)^Access-Control-Allow-Headers:.*$([regex]::Escape($header))") { throw "Required CORS preflight header was not allowed: $header" }
}
if($allowedPreflight -notmatch "(?im)^Access-Control-Allow-Methods:.*POST") { throw "Required CORS preflight method was not allowed: POST" }
$rejectedPreflight=Preflight "X-Unapproved-Header"
if($rejectedPreflight -match "(?im)^Access-Control-Allow-Origin:") { throw "Unapproved CORS request header was allowed" }
Write-Host "PASS: API/web security headers present, both local console origins and required headers allowed, untrusted origin/header rejected"
