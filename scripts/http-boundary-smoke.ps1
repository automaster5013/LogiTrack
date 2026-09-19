$ErrorActionPreference = "Stop"
function Headers([string]$url,[string]$origin="") {
  $arguments=@("-sS","-D","-","-o","NUL")
  if($origin){$arguments+=@("-H","Origin: $origin")}
  return (curl.exe @arguments $url) -join "`n"
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
Write-Host "PASS: API/web security headers present, trusted CORS allowed, untrusted CORS rejected"
