$ErrorActionPreference = "Stop"

function Send-Telemetry($event) {
  $event | ConvertTo-Json -Depth 5 -Compress | docker compose exec -T kafka /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server kafka:29092 --topic vehicle.telemetry.v1
  if ($LASTEXITCODE -ne 0) { throw "Could not publish order telemetry" }
}

docker compose stop simulator | Out-Null
try {
  $suffix = [guid]::NewGuid().ToString("N").Substring(0,8)
  $orderKey = "order-smoke-$suffix"
  $orderBody = @{orderNumber="ORD-FLOW-$suffix";origin=@{name="Seoul Hub";lat=37.5665;lon=126.978};destination=@{name="Incheon DC";lat=37.4563;lon=126.7052}} | ConvertTo-Json -Depth 4
  $created = Invoke-RestMethod http://localhost:8080/api/orders -Method Post -Headers @{"Idempotency-Key"=$orderKey} -ContentType "application/json" -Body $orderBody
  $duplicate = Invoke-RestMethod http://localhost:8080/api/orders -Method Post -Headers @{"Idempotency-Key"=$orderKey} -ContentType "application/json" -Body $orderBody
  if ($created.id -ne $duplicate.id) { throw "Order idempotency returned a different order" }
  if ($created.status -ne "READY" -or $created.deliveryId) { throw "New order is not independently READY" }

  $dispatchKey = "dispatch-smoke-$suffix"
  $dispatchBody = @{vehicleId="TRUCK-ORDER-$suffix"} | ConvertTo-Json
  $dispatched = Invoke-RestMethod "http://localhost:8080/api/orders/$($created.id)/dispatch" -Method Post -Headers @{"Idempotency-Key"=$dispatchKey} -ContentType "application/json" -Body $dispatchBody
  $dispatchAgain = Invoke-RestMethod "http://localhost:8080/api/orders/$($created.id)/dispatch" -Method Post -Headers @{"Idempotency-Key"=$dispatchKey} -ContentType "application/json" -Body $dispatchBody
  if ($dispatched.status -ne "DISPATCHED" -or -not $dispatched.deliveryId) { throw "Order was not linked to a delivery" }
  if ($dispatched.deliveryId -ne $dispatchAgain.deliveryId) { throw "Repeat dispatch created another delivery" }

  $telemetryId = [guid]::NewGuid().ToString()
  Send-Telemetry @{eventId=$telemetryId;eventType="vehicle.telemetry.v1";occurredAt=(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ");traceId=[guid]::NewGuid().ToString();schemaVersion=1;payload=@{deliveryId=$dispatched.deliveryId;vehicleId=$dispatched.vehicleId;lat=37.4563;lon=126.7052;progress=1;status="DELIVERED";eta=(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")}}

  $deadline = (Get-Date).AddSeconds(45)
  do {
    Start-Sleep -Seconds 2
    $order = @((Invoke-RestMethod http://localhost:8080/api/orders)) | Where-Object {$_.id -eq $created.id} | Select-Object -First 1
  } while ($order.status -ne "FULFILLED" -and (Get-Date) -lt $deadline)
  if ($order.status -ne "FULFILLED" -or $order.deliveryStatus -ne "DELIVERED") { throw "Delivery completion did not fulfill the order" }

  $deadline = (Get-Date).AddSeconds(20)
  do {
    Start-Sleep -Seconds 1
    $published = docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT count(*) FROM outbox_events WHERE aggregate_id='$($created.id)' AND aggregate_type='ORDER' AND status='PUBLISHED'"
  } while ([int]$published.Trim() -lt 3 -and (Get-Date) -lt $deadline)
  if ([int]$published.Trim() -ne 3) { throw "Expected three published order lifecycle events, got $published" }

  $linked = docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT count(*) FROM deliveries WHERE order_id='$($created.id)'"
  if ([int]$linked.Trim() -ne 1) { throw "Expected exactly one delivery linked to the order" }
  Write-Host "PASS: order=$($created.id), delivery=$($dispatched.deliveryId), lifecycle=READY->DISPATCHED->FULFILLED, events=3"
}
finally {
  docker compose up -d --no-deps simulator | Out-Null
  $deadline = (Get-Date).AddSeconds(30)
  do {
    $simulatorState = docker inspect logitrack-simulator-1 --format "{{.State.Status}}" 2>$null
    if ($simulatorState -eq "running") { break }
    Start-Sleep -Seconds 1
  } while ((Get-Date) -lt $deadline)
  if ($simulatorState -ne "running") { throw "Simulator was not restored after the order smoke test" }
  if ($created -and $dispatched) {
    Start-Sleep -Seconds 8
    $restoredDelivery = @((Invoke-RestMethod http://localhost:8080/api/deliveries)) | Where-Object {$_.id -eq $dispatched.deliveryId} | Select-Object -First 1
    $restoredOrder = @((Invoke-RestMethod http://localhost:8080/api/orders)) | Where-Object {$_.id -eq $created.id} | Select-Object -First 1
    if ($restoredDelivery.status -ne "DELIVERED" -or $restoredOrder.status -ne "FULFILLED") {
      throw "Late simulator telemetry regressed a completed order or delivery"
    }
  }
}
