$ErrorActionPreference = "Stop"
$suffix = [guid]::NewGuid().ToString("N").Substring(0,8)
$body = @{
  orderNumber="ORD-MAP-SCOPE-$suffix"
  vehicleId="TRUCK-MAP-SCOPE-$suffix"
  origin=@{name="Seoul Hub";lat=37.5665;lon=126.978}
  destination=@{name="Incheon DC";lat=37.4563;lon=126.7052}
} | ConvertTo-Json -Depth 4
$created = Invoke-RestMethod http://localhost:8080/api/deliveries -Method Post -Headers @{"Idempotency-Key"="map-scope-$suffix"} -ContentType "application/json" -Body $body
$deadline = (Get-Date).AddSeconds(30)
do {
  Start-Sleep -Seconds 1
  $points = @(Invoke-RestMethod "http://localhost:8080/api/telemetry/points?deliveryIds=$($created.id)")
} while ($points.Count -lt 1 -and (Get-Date) -lt $deadline)
$routes = @(Invoke-RestMethod "http://localhost:8080/api/routes?deliveryIds=$($created.id)")
if ($routes.Count -lt 1 -or $points.Count -lt 1) { throw "Scoped map data is incomplete" }
if (@($routes | Where-Object { $_.deliveryId -ne $created.id }).Count -or @($points | Where-Object { $_.deliveryId -ne $created.id }).Count) { throw "Scoped map API leaked another delivery" }
$newRouteId = [guid]::NewGuid().ToString()
$sql = "INSERT INTO route_snapshots (id,delivery_id,provider,algorithm_version,geometry,geometry_hash,distance_meters,duration_seconds,planned_eta,generated_at) SELECT '$newRouteId',delivery_id,'scope-smoke-latest',algorithm_version,geometry,geometry_hash,distance_meters,duration_seconds,planned_eta + interval '1 minute',generated_at + interval '1 minute' FROM route_snapshots WHERE delivery_id='$($created.id)' ORDER BY generated_at DESC LIMIT 1"
docker compose exec -T postgres psql -U logitrack -d logitrack -v ON_ERROR_STOP=1 -c $sql | Out-Null
$routes = @(Invoke-RestMethod "http://localhost:8080/api/routes?deliveryIds=$($created.id)")
if ($routes.Count -ne 1 -or $routes[0].provider -ne "scope-smoke-latest") { throw "Scoped route API did not return only the latest snapshot" }
$allRouteBytes = (Invoke-WebRequest http://localhost:8080/api/routes -UseBasicParsing).Content.Length
$scopedRouteBytes = (Invoke-WebRequest "http://localhost:8080/api/routes?deliveryIds=$($created.id)" -UseBasicParsing).Content.Length
if ($scopedRouteBytes -ge $allRouteBytes) { throw "Scoped route response was not smaller than the unfiltered response" }
Write-Host "PASS: delivery=$($created.id), latestRoutes=$($routes.Count), points=$($points.Count), routeBytes=$scopedRouteBytes/$allRouteBytes"
