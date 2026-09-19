$ErrorActionPreference = "Stop"
$suffix = [guid]::NewGuid().ToString("N").Substring(0,8)
$body = @{
  orderNumber="ORD-TRACK-$suffix"
  vehicleId="TRUCK-TRACK-$suffix"
  origin=@{name="Seoul Hub";lat=37.5665;lon=126.978}
  destination=@{name="Incheon DC";lat=37.4563;lon=126.7052}
} | ConvertTo-Json -Depth 4
$created = Invoke-RestMethod http://localhost:8080/api/deliveries -Method Post -Headers @{"Idempotency-Key"="track-$suffix"} -ContentType "application/json" -Body $body
$deadline = (Get-Date).AddSeconds(30)
do {
  Start-Sleep -Seconds 1
  $points = @((Invoke-RestMethod http://localhost:8080/api/telemetry/points) | Where-Object deliveryId -eq $created.id)
} while ($points.Count -lt 2 -and (Get-Date) -lt $deadline)
if ($points.Count -lt 2) { throw "Telemetry history did not expose at least two actual positions" }
$persisted = docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT count(*) FROM telemetry_points WHERE delivery_id = '$($created.id)'"
if ([int]$persisted.Trim() -lt 2) { throw "PostgreSQL telemetry history is incomplete: $persisted" }
$eventIds = @($points | Select-Object -ExpandProperty eventId -Unique)
if ($eventIds.Count -ne $points.Count) { throw "Telemetry event idempotency was violated" }
if (@($points | Where-Object { $_.latitude -lt -90 -or $_.latitude -gt 90 -or $_.longitude -lt -180 -or $_.longitude -gt 180 }).Count) { throw "Invalid coordinates were returned" }
Write-Host "PASS: delivery=$($created.id), apiPoints=$($points.Count), persistedPoints=$($persisted.Trim())"
