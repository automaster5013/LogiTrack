$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

function Invoke-Compose([string[]]$Arguments) {
  & docker compose @Arguments
  if ($LASTEXITCODE -ne 0) { throw "docker compose $($Arguments -join ' ') failed" }
}

function Wait-Endpoint([string]$Url, [int]$TimeoutSeconds = 90) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    try {
      $response = Invoke-WebRequest -UseBasicParsing $Url -TimeoutSec 3
      if ($response.StatusCode -eq 200) { return }
    } catch {}
    Start-Sleep -Seconds 2
  } while ((Get-Date) -lt $deadline)
  throw "Endpoint did not recover within ${TimeoutSeconds}s: $Url"
}

function New-DrillDelivery([string]$Label) {
  $suffix = [guid]::NewGuid().ToString("N").Substring(0, 8)
  $body = @{
    orderNumber = "ORD-$Label-$suffix"
    vehicleId = "TRUCK-$Label-$suffix"
    origin = @{name="Seoul Hub";lat=37.5665;lon=126.978}
    destination = @{name="Incheon DC";lat=37.4563;lon=126.7052}
  } | ConvertTo-Json -Depth 4
  Invoke-RestMethod http://localhost:8080/api/deliveries -Method Post `
    -Headers @{"Idempotency-Key"="recovery-$Label-$suffix"} -ContentType "application/json" -Body $body
}

function Wait-Route([string]$DeliveryId, [int]$TimeoutSeconds = 20) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    $route = @((Invoke-RestMethod http://localhost:8080/api/routes)) |
      Where-Object { $_.deliveryId -eq $DeliveryId } | Select-Object -First 1
    if ($route) { return $route }
    Start-Sleep -Seconds 1
  } while ((Get-Date) -lt $deadline)
  throw "Route snapshot was not created for $DeliveryId"
}

function Send-Telemetry([object]$Delivery, [string]$EventId, [double]$Progress) {
  $event = @{
    eventId = $EventId
    eventType = "vehicle.telemetry.v1"
    occurredAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    traceId = [guid]::NewGuid().ToString()
    schemaVersion = 1
    payload = @{
      deliveryId = $Delivery.id
      vehicleId = $Delivery.vehicleId
      lat = 37.52
      lon = 126.84
      progress = $Progress
      status = "IN_TRANSIT"
      eta = (Get-Date).ToUniversalTime().AddMinutes(25).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }
  }
  $event | ConvertTo-Json -Depth 5 -Compress |
    docker compose exec -T kafka /opt/kafka/bin/kafka-console-producer.sh `
      --bootstrap-server kafka:29092 --topic vehicle.telemetry.v1
  if ($LASTEXITCODE -ne 0) { throw "Could not publish recovery telemetry" }
}

function Wait-DeliveryProgress([string]$DeliveryId, [double]$Expected, [int]$TimeoutSeconds = 60) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    try {
      $delivery = @((Invoke-RestMethod http://localhost:8080/api/deliveries)) |
        Where-Object { $_.id -eq $DeliveryId } | Select-Object -First 1
      if ($delivery -and [double]$delivery.progress -ge $Expected) { return $delivery }
    } catch {}
    Start-Sleep -Seconds 2
  } while ((Get-Date) -lt $deadline)
  throw "Delivery $DeliveryId did not reach progress $Expected"
}

function Get-RedisErrorFallbackCount {
  $metrics = (Invoke-WebRequest -UseBasicParsing http://localhost:8080/actuator/prometheus).Content
  $line = ($metrics -split "`n" | Where-Object {
    $_ -match '^logitrack_sse_fallback_total\{' -and $_ -match 'reason="redis_error"'
  } | Select-Object -First 1)
  if (-not $line) { return [double]0 }
  return [double]::Parse(($line -split '\s+')[-1], [Globalization.CultureInfo]::InvariantCulture)
}

$analyticsStopped = $false
$apiStopped = $false
$redisStopped = $false
$simulatorStopped = $false

Wait-Endpoint http://localhost:8080/actuator/health/readiness
Wait-Endpoint http://localhost:8090/health

try {
  Invoke-Compose @("stop", "simulator") | Out-Null
  $simulatorStopped = $true

  Write-Host "[1/3] Injecting analytics outage and verifying route fallback"
  Invoke-Compose @("stop", "analytics") | Out-Null
  $analyticsStopped = $true
  $fallbackDelivery = New-DrillDelivery "FALLBACK"
  $fallbackRoute = Wait-Route $fallbackDelivery.id
  if ($fallbackRoute.provider -ne "spring-fallback") {
    throw "Expected spring-fallback route, got $($fallbackRoute.provider)"
  }
  Invoke-Compose @("start", "analytics") | Out-Null
  $analyticsStopped = $false
  Wait-Endpoint http://localhost:8090/health

  Write-Host "[2/3] Killing the consumer, buffering telemetry in Kafka, and recovering"
  Invoke-Compose @("kill", "-s", "KILL", "api") | Out-Null
  $apiStopped = $true
  $recoveryEventId = [guid]::NewGuid().ToString()
  Send-Telemetry $fallbackDelivery $recoveryEventId 0.42
  Invoke-Compose @("start", "api") | Out-Null
  $apiStopped = $false
  Wait-Endpoint http://localhost:8080/actuator/health/readiness
  $recovered = Wait-DeliveryProgress $fallbackDelivery.id 0.42
  $processed = Invoke-Compose @("exec", "-T", "postgres", "psql", "-U", "logitrack", "-d", "logitrack", "-tAc", "SELECT count(*) FROM processed_events WHERE event_id='$recoveryEventId' AND consumer_name='control-api-telemetry-v1'")
  if ([int](($processed | Out-String).Trim()) -ne 1) { throw "Recovered telemetry was not processed exactly once" }

  Write-Host "[3/3] Injecting Redis outage and verifying DB writes plus local SSE fallback"
  $fallbackBefore = Get-RedisErrorFallbackCount
  Invoke-Compose @("stop", "redis") | Out-Null
  $redisStopped = $true
  $redisDelivery = New-DrillDelivery "REDIS"
  $redisEventId = [guid]::NewGuid().ToString()
  Send-Telemetry $redisDelivery $redisEventId 0.25
  $redisRecoveredWrite = Wait-DeliveryProgress $redisDelivery.id 0.25 90
  $fallbackAfter = Get-RedisErrorFallbackCount
  if ($fallbackAfter -le $fallbackBefore) { throw "Redis error did not increment the SSE fallback counter" }
  Invoke-Compose @("start", "redis") | Out-Null
  $redisStopped = $false
  Wait-Endpoint http://localhost:8080/actuator/health/readiness

  Write-Host "PASS: routeFallback=$($fallbackRoute.provider), consumerEvent=$recoveryEventId, recoveredProgress=$($recovered.progress), redisDelivery=$($redisRecoveredWrite.id), redisFallbackDelta=$($fallbackAfter - $fallbackBefore)"
}
finally {
  if ($redisStopped) { try { Invoke-Compose @("start", "redis") | Out-Null } catch { Write-Warning $_ } }
  if ($analyticsStopped) { try { Invoke-Compose @("start", "analytics") | Out-Null } catch { Write-Warning $_ } }
  if ($apiStopped) { try { Invoke-Compose @("start", "api") | Out-Null } catch { Write-Warning $_ } }
  if ($simulatorStopped) { try { Invoke-Compose @("start", "simulator") | Out-Null } catch { Write-Warning $_ } }
}
