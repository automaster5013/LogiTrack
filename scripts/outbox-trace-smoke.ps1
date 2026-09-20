$ErrorActionPreference = "Stop"
$traceId = ([guid]::NewGuid().ToString("N") + [guid]::NewGuid().ToString("N")).Substring(0,32)
$parentSpanId = [guid]::NewGuid().ToString("N").Substring(0,16)
$suffix = [guid]::NewGuid().ToString("N").Substring(0,8)
$key = "outbox-trace-smoke-$suffix"
$body = @{orderNumber="TRACE-$suffix";origin=@{name="Seoul";lat=37.5665;lon=126.978};destination=@{name="Incheon";lat=37.4563;lon=126.7052}} | ConvertTo-Json -Depth 4
$order = $null
try {
  $order = Invoke-RestMethod http://localhost:8080/api/orders -Method Post -Headers @{"Idempotency-Key"=$key;traceparent="00-$traceId-$parentSpanId-01"} -ContentType "application/json" -Body $body
  $deadline = (Get-Date).AddSeconds(30)
  do {
    $row = (docker compose exec -T postgres psql -U logitrack -d logitrack -tA -F '|' -c "SELECT origin_trace_id,origin_span_id,origin_trace_sampled,status FROM outbox_events WHERE aggregate_id='$($order.id)' AND event_type='order.created.v1'").Trim()
    if($row){$storedTrace,$storedSpan,$sampled,$status=$row.Split('|',4)}
    if($row -and $status -eq 'PUBLISHED'){break}
    Start-Sleep -Milliseconds 500
  } while((Get-Date) -lt $deadline)
  if($storedTrace -ne $traceId -or $storedSpan -notmatch '^[0-9a-f]{16}$' -or $sampled -ne 't' -or $status -ne 'PUBLISHED') { throw "Outbox trace context was not persisted and published: $row" }

  $traceDeadline = (Get-Date).AddSeconds(30)
  do {
    try {$trace = (Invoke-WebRequest "http://localhost:3200/api/traces/$traceId" -UseBasicParsing).Content} catch {$trace = ""}
    if($trace -match 'outbox publish'){break}
    Start-Sleep -Seconds 1
  } while((Get-Date) -lt $traceDeadline)
  if($trace -notmatch 'outbox publish') { throw "Tempo did not receive the asynchronous outbox producer span in trace $traceId" }
  Write-Host "PASS: HTTP trace $traceId persisted in outbox and continued through the asynchronous producer span"
} finally {
  if($order) {
    docker compose exec -T postgres psql -U logitrack -d logitrack -v ON_ERROR_STOP=1 -c "DELETE FROM outbox_events WHERE aggregate_id='$($order.id)';DELETE FROM orders WHERE id='$($order.id)';" | Out-Null
  }
}
