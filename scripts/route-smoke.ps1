$ErrorActionPreference = "Stop"
$suffix = [guid]::NewGuid().ToString("N").Substring(0,8)
$body = @{
  orderNumber="ORD-ROUTE-$suffix"
  vehicleId="TRUCK-ROUTE-$suffix"
  origin=@{name="Seoul Hub";lat=37.5665;lon=126.978}
  destination=@{name="Incheon DC";lat=37.4563;lon=126.7052}
} | ConvertTo-Json -Depth 4
$created = Invoke-RestMethod http://localhost:8080/api/deliveries -Method Post -Headers @{"Idempotency-Key"="route-$suffix"} -ContentType "application/json" -Body $body
$route = (Invoke-RestMethod http://localhost:8080/api/routes) | Where-Object deliveryId -eq $created.id | Select-Object -First 1
if (-not $route) { throw "Route snapshot was not persisted" }
if ($route.geometry.type -ne "LineString" -or $route.geometry.coordinates.Count -lt 2) { throw "Route geometry is invalid" }
if ($route.distanceMeters -le 0 -or $route.durationSeconds -le 0) { throw "Route metrics are invalid" }
if ([string]::IsNullOrWhiteSpace($route.provider)) { throw "Route provider is missing" }
$deadline = (Get-Date).AddSeconds(20)
do {
  Start-Sleep -Seconds 1
  $delivery = (Invoke-RestMethod http://localhost:8080/api/deliveries) | Where-Object id -eq $created.id
} while ($delivery.status -eq "CREATED" -and (Get-Date) -lt $deadline)
if ($delivery.status -notin @("IN_TRANSIT","DELIVERED")) { throw "Route telemetry was not applied" }
$persisted = docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT count(*) FROM route_snapshots WHERE delivery_id = '$($created.id)' AND geometry_hash = '$($route.geometryHash)'"
if ([int]$persisted.Trim() -ne 1) { throw "Route snapshot persistence mismatch" }
Write-Host "PASS: delivery=$($created.id), provider=$($route.provider), points=$($route.geometry.coordinates.Count), distance=$($route.distanceMeters)m, progress=$($delivery.progress)"
