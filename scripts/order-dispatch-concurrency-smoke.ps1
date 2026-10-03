$ErrorActionPreference = "Stop"
$suffix = [guid]::NewGuid().ToString("N").Substring(0,8)
$orderBody = @{orderNumber="ORD-CONCURRENT-$suffix";origin=@{name="Seoul Hub";lat=37.5665;lon=126.978};destination=@{name="Incheon DC";lat=37.4563;lon=126.7052}} | ConvertTo-Json -Depth 4
$order = Invoke-RestMethod http://localhost:8080/api/orders -Method Post -Headers @{"Idempotency-Key"="order-concurrent-$suffix"} -ContentType "application/json" -Body $orderBody
$dispatchBody = @{vehicleId="TRUCK-CONCURRENT-$suffix"} | ConvertTo-Json
$dispatchKey = "dispatch-concurrent-$suffix"
$jobs = 1..2 | ForEach-Object {
  Start-Job -ScriptBlock {
    param($orderId,$key,$body)
    try {
      $value = Invoke-RestMethod "http://localhost:8080/api/orders/$orderId/dispatch" -Method Post -Headers @{"Idempotency-Key"=$key} -ContentType "application/json" -Body $body
      [pscustomobject]@{ok=$true;status=$value.status;deliveryId=$value.deliveryId}
    } catch {
      [pscustomobject]@{ok=$false;status=$_.Exception.Response.StatusCode.value__;deliveryId=$null}
    }
  } -ArgumentList $order.id,$dispatchKey,$dispatchBody
}
$results = @($jobs | Wait-Job | Receive-Job)
$jobs | Remove-Job
if (@($results | Where-Object {-not $_.ok -or $_.status -ne "DISPATCHED"}).Count -ne 0) {
  throw "Concurrent order dispatch requests did not both resolve idempotently: $($results | ConvertTo-Json -Compress)"
}
$deliveryIds = @($results.deliveryId | Sort-Object -Unique)
if ($deliveryIds.Count -ne 1) { throw "Concurrent order dispatch created different deliveries: $($deliveryIds -join ',')" }
$deliveryCount = (docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT count(*) FROM deliveries WHERE order_id='$($order.id)'").Trim()
$eventCount = (docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT count(*) FROM outbox_events WHERE aggregate_id='$($order.id)' AND event_type='order.dispatched.v1'").Trim()
$storedKey = (docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT dispatch_request_key FROM orders WHERE id='$($order.id)'").Trim()
if ([int]$deliveryCount -ne 1 -or [int]$eventCount -ne 1 -or $storedKey -ne $dispatchKey) {
  throw "Concurrent order dispatch was not persisted once: deliveries=$deliveryCount events=$eventCount key=$storedKey"
}
Write-Host "PASS: order=$($order.id), concurrent dispatch returned one delivery=$($deliveryIds[0]) and one lifecycle event"
