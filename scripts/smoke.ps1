$ErrorActionPreference = "Stop"
$health = Invoke-RestMethod http://localhost:8080/actuator/health/readiness
if ($health.status -ne "UP") { throw "API is not ready" }
$key = "smoke-" + [guid]::NewGuid().ToString()
$body = @{orderNumber="ORD-SMOKE";vehicleId="TRUCK-SMOKE";origin=@{name="Seoul";lat=37.5665;lon=126.978};destination=@{name="Incheon";lat=37.4563;lon=126.7052}} | ConvertTo-Json -Depth 4
$created = Invoke-RestMethod http://localhost:8080/api/deliveries -Method Post -Headers @{"Idempotency-Key"=$key} -ContentType "application/json" -Body $body
$duplicate = Invoke-RestMethod http://localhost:8080/api/deliveries -Method Post -Headers @{"Idempotency-Key"=$key} -ContentType "application/json" -Body $body
if ($created.id -ne $duplicate.id) { throw "Idempotency failed" }
$deadline = (Get-Date).AddSeconds(30)
do {
  Start-Sleep -Seconds 2
  $delivery = (Invoke-RestMethod http://localhost:8080/api/deliveries) | Where-Object id -eq $created.id
} while ($delivery.status -notin @("IN_TRANSIT","DELIVERED") -and (Get-Date) -lt $deadline)
if ($delivery.status -notin @("IN_TRANSIT","DELIVERED")) { throw "Telemetry was not applied" }
$outbox = docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT status FROM outbox_events WHERE aggregate_id = '$($created.id)'"
if ($outbox.Trim() -ne "PUBLISHED") { throw "Outbox event was not published: $outbox" }
Write-Host "PASS: delivery=$($created.id), status=$($delivery.status), progress=$($delivery.progress), outbox=$($outbox.Trim())"
