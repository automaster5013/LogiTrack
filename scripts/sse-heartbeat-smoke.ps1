$ErrorActionPreference = "Stop"
$output = curl.exe -sN --max-time 20 http://localhost:8080/api/stream/deliveries 2>$null
if($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 28){throw "SSE request failed with curl exit code $LASTEXITCODE"}
$text = $output -join "`n"
if($text -notmatch "event:connected"){throw "SSE connected event was not received"}
if($text -notmatch ":keepalive"){throw "SSE heartbeat comment was not received within 20 seconds"}
Write-Host "PASS: SSE connected event and idle keepalive heartbeat received"
