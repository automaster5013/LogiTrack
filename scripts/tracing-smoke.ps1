$ErrorActionPreference = "Stop"

$readyDeadline = (Get-Date).AddSeconds(60)
do {
  Start-Sleep -Seconds 2
  try { $collectorReady = (Invoke-RestMethod http://localhost:13133/).status -eq "Server available" } catch { $collectorReady = $false }
  try { $tempoReady = (Invoke-WebRequest -UseBasicParsing http://localhost:3200/ready).StatusCode -eq 200 } catch { $tempoReady = $false }
} while ((-not $collectorReady -or -not $tempoReady) -and (Get-Date) -lt $readyDeadline)
if (-not $collectorReady) { throw "OpenTelemetry Collector is not ready" }
if (-not $tempoReady) { throw "Tempo is not ready" }

$traceId = [guid]::NewGuid().ToString("N")
$spanId = [guid]::NewGuid().ToString("N").Substring(0,16)
$suffix = $traceId.Substring(0,8)
$body = @{orderNumber="ORD-TRACE-$suffix";vehicleId="TRUCK-TRACE-$suffix";origin=@{name="Seoul";lat=37.5665;lon=126.978};destination=@{name="Incheon";lat=37.4563;lon=126.7052}} | ConvertTo-Json -Depth 4
$created = Invoke-RestMethod http://localhost:8080/api/deliveries -Method Post -Headers @{"Idempotency-Key"="trace-$suffix";traceparent="00-$traceId-$spanId-01"} -ContentType "application/json" -Body $body

$deadline = (Get-Date).AddSeconds(40)
do {
  Start-Sleep -Seconds 2
  try { $trace = Invoke-RestMethod "http://localhost:3200/api/traces/$traceId"; $traceJson = $trace | ConvertTo-Json -Depth 20 -Compress } catch { $traceJson = "" }
} while (($traceJson -notmatch "logitrack-control-api" -or $traceJson -notmatch "logitrack-route-analytics") -and (Get-Date) -lt $deadline)

if ($traceJson -notmatch "logitrack-control-api") { throw "Control API spans were not stored in Tempo" }
if ($traceJson -notmatch "logitrack-route-analytics") { throw "Analytics child spans were not correlated in Tempo" }
Write-Host "PASS: delivery=$($created.id), trace=$traceId, services=control-api+route-analytics"
