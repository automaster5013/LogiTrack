$ErrorActionPreference = "Stop"

function Send-Telemetry($event) {
  $event | ConvertTo-Json -Depth 5 -Compress | docker compose exec -T kafka /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server kafka:29092 --topic vehicle.telemetry.v1
  if ($LASTEXITCODE -ne 0) { throw "Could not publish telemetry" }
}

docker compose stop simulator | Out-Null
try {
  $suffix = [guid]::NewGuid().ToString("N").Substring(0,8)
  $body = @{orderNumber="ORD-ALERT-$suffix";vehicleId="TRUCK-ALERT-$suffix";origin=@{name="Seoul";lat=37.5665;lon=126.978};destination=@{name="Incheon";lat=37.4563;lon=126.7052}} | ConvertTo-Json -Depth 4
  $created = Invoke-RestMethod http://localhost:8080/api/deliveries -Method Post -Headers @{"Idempotency-Key"="alert-$suffix"} -ContentType "application/json" -Body $body

  1..2 | ForEach-Object {
    Send-Telemetry @{eventId=[guid]::NewGuid().ToString();eventType="vehicle.telemetry.v1";occurredAt=(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ");traceId=[guid]::NewGuid().ToString();schemaVersion=1;payload=@{deliveryId=$created.id;vehicleId=$created.vehicleId;lat=38.2;lon=127.8;progress=0.2;status="DELAYED";eta=(Get-Date).ToUniversalTime().AddHours(2).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")}}
  }
  Start-Sleep -Seconds 3
  $active = (Invoke-RestMethod http://localhost:8080/api/alerts) | Where-Object {$_.deliveryId -eq $created.id -and $_.status -eq "ACTIVE"}
  if ($active.Count -ne 2) { throw "Expected exactly two active alerts, got $($active.Count)" }
  if (($active | Where-Object alertType -eq "ROUTE_DEVIATION").severity -ne "CRITICAL") { throw "Route deviation was not escalated" }
  if (($active | Where-Object {$_.occurrenceCount -ne 2}).Count -ne 0) { throw "Repeated observations did not update the existing alerts" }

  Send-Telemetry @{eventId=[guid]::NewGuid().ToString();eventType="vehicle.telemetry.v1";occurredAt=(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ");traceId=[guid]::NewGuid().ToString();schemaVersion=1;payload=@{deliveryId=$created.id;vehicleId=$created.vehicleId;lat=37.5665;lon=126.978;progress=0.25;status="IN_TRANSIT";eta=(Get-Date).ToUniversalTime().AddMinutes(1).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")}}
  Start-Sleep -Seconds 3
  $resolved = (Invoke-RestMethod http://localhost:8080/api/alerts) | Where-Object {$_.deliveryId -eq $created.id -and $_.status -eq "RESOLVED"}
  if ($resolved.Count -ne 2) { throw "Expected both alerts to resolve, got $($resolved.Count)" }
  $published = docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT count(*) FROM outbox_events WHERE aggregate_type='DELIVERY_ALERT' AND payload LIKE '%$($created.id)%' AND status='PUBLISHED'"
  if ([int]$published.Trim() -ne 4) { throw "Expected four lifecycle events, got $published" }
  Write-Host "PASS: delivery=$($created.id), active=2, deduplicated observations=2, resolved=2, lifecycle events=4"
}
finally {
  docker compose start simulator | Out-Null
}

