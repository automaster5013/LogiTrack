$ErrorActionPreference = "Stop"

docker compose --profile scale-test build api-replica | Out-Null
docker compose --profile scale-test up -d --no-deps --force-recreate api-replica | Out-Null
try {
  $deadline = (Get-Date).AddSeconds(60)
  do {
    Start-Sleep -Seconds 2
    try { $ready = (Invoke-RestMethod http://localhost:8081/actuator/health/readiness).status } catch { $ready = "DOWN" }
  } while ($ready -ne "UP" -and (Get-Date) -lt $deadline)
  if ($ready -ne "UP") { throw "API replica did not become ready" }

  $streamJob = Start-Job -ScriptBlock { curl.exe -sN --max-time 12 http://localhost:8081/api/stream/deliveries }
  Start-Sleep -Seconds 2
  $suffix = [guid]::NewGuid().ToString("N").Substring(0,8)
  $body = @{orderNumber="ORD-FANOUT-$suffix";vehicleId="TRUCK-FANOUT-$suffix";origin=@{name="Seoul";lat=37.5665;lon=126.978};destination=@{name="Incheon";lat=37.4563;lon=126.7052}} | ConvertTo-Json -Depth 4
  $created = Invoke-RestMethod http://localhost:8080/api/deliveries -Method Post -Headers @{"Idempotency-Key"="fanout-$suffix"} -ContentType "application/json" -Body $body
  Wait-Job $streamJob -Timeout 10 | Out-Null
  $events = (Receive-Job $streamJob -Keep) -join "`n"
  if ($events -notmatch '"instanceId":"api-replica"') { throw "Replica SSE connection was not established" }
  if ($events -notmatch $created.id) { throw "Primary delivery update did not reach replica SSE" }
  if ($events -notmatch 'event:telemetry-point') { throw "Incremental telemetry point did not reach replica SSE" }
  Write-Host "PASS: delivery and incremental telemetry reached replica SSE, delivery=$($created.id)"
}
finally {
  if ($streamJob) { Stop-Job $streamJob -ErrorAction SilentlyContinue; Remove-Job $streamJob -Force -ErrorAction SilentlyContinue }
  docker compose stop api-replica | Out-Null
}
