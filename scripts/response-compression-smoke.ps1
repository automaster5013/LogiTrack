$ErrorActionPreference = "Stop"
$url = "http://localhost:8080/api/routes"
$identity = [long](curl.exe -sS -H "Accept-Encoding: identity" -o NUL -w "%{size_download}" $url)
$compressedResponse = (curl.exe -sS -H "Accept-Encoding: gzip" -o NUL -D - -w "SIZE:%{size_download}" $url) -join "`n"
if ($compressedResponse -notmatch "(?im)^Content-Encoding:\s*gzip\s*$") { throw "Route response was not gzip encoded" }
if ($compressedResponse -notmatch "SIZE:(\d+)") { throw "Could not measure compressed route response" }
$compressed = [long]$Matches[1]
if ($identity -lt 1024) { throw "Route response is too small to exercise compression: $identity bytes" }
if ($compressed -ge ($identity * 0.5)) { throw "Compressed route response did not save at least 50%: $compressed/$identity bytes" }
$savedPercent = [math]::Round((1 - ($compressed / $identity)) * 100, 1)
Write-Host "PASS: encoding=gzip, routeBytes=$compressed/$identity, saved=$savedPercent%"
