$ErrorActionPreference = "Stop"
function Headers([string]$url,[string]$origin="") {
  $arguments=@("-sS","-D","-","-o","NUL")
  if($origin){$arguments+=@("-H","Origin: $origin")}
  return (curl.exe @arguments $url) -join "`n"
}
function Preflight([string]$requestHeaders) {
  return (curl.exe -sS -D - -o NUL -X OPTIONS `
    -H "Origin: http://localhost:3000" `
    -H "Access-Control-Request-Method: POST" `
    -H "Access-Control-Request-Headers: $requestHeaders" `
    http://localhost:8080/api/deliveries) -join "`n"
}
$api=Headers "http://localhost:8080/api/deliveries" "http://localhost:3000"
$untrusted=Headers "http://localhost:8080/api/deliveries" "https://untrusted.example"
$web=Headers "http://localhost:3000"
foreach($header in @("Content-Security-Policy: frame-ancestors 'none'","X-Content-Type-Options: nosniff","X-Frame-Options: DENY","Referrer-Policy: no-referrer","Permissions-Policy: camera=(), microphone=(), geolocation=()")) {
  if($api -notmatch "(?im)^$([regex]::Escape($header))\s*$") { throw "API security header is missing: $header" }
  if($web -notmatch "(?im)^$([regex]::Escape($header))\s*$") { throw "Web security header is missing: $header" }
}
if($api -notmatch "(?im)^Access-Control-Allow-Origin:\s*http://localhost:3000\s*$") { throw "Trusted web origin was not allowed" }
if($untrusted -match "(?im)^Access-Control-Allow-Origin:") { throw "Untrusted origin was allowed" }
$allowedPreflight=Preflight "Content-Type, Idempotency-Key, X-Trace-Id"
if($allowedPreflight -notmatch "(?im)^Access-Control-Allow-Methods:.*POST" -or $allowedPreflight -notmatch "(?im)^Access-Control-Allow-Headers:.*Idempotency-Key") { throw "Required CORS preflight headers were not allowed" }
$rejectedPreflight=Preflight "Authorization"
if($rejectedPreflight -match "(?im)^Access-Control-Allow-Origin:") { throw "Unapproved CORS request header was allowed" }
Write-Host "PASS: API/web security headers present, trusted CORS origin and required headers allowed, untrusted origin/header rejected"
