$ErrorActionPreference = "Stop"

function Send-Telemetry($event) {
  $event | ConvertTo-Json -Depth 5 -Compress | docker compose exec -T kafka /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server kafka:29092 --topic vehicle.telemetry.v1
  if ($LASTEXITCODE -ne 0) { throw "Could not publish telemetry" }
}

function Save-Policy($vehicleId, $deviationOpen, $deviationClose, $deviationCritical, $delayOpen, $delayClose, $delayCritical) {
  $body = @{
    vehicleId=$vehicleId; deviationOpenMeters=$deviationOpen; deviationCloseMeters=$deviationClose; criticalDeviationMeters=$deviationCritical
    delayOpenSeconds=$delayOpen; delayCloseSeconds=$delayClose; criticalDelaySeconds=$delayCritical
  } | ConvertTo-Json
  Invoke-RestMethod http://localhost:8080/api/alert-policies -Method Post -Headers @{"X-Operator"="policy-smoke"} -ContentType "application/json" -Body $body
}

docker compose stop simulator | Out-Null
try {
  $suffix = [guid]::NewGuid().ToString("N").Substring(0,8)
  $vehicle = "TRUCK-POLICY-$suffix"
  $body = @{orderNumber="ORD-POLICY-$suffix";vehicleId=$vehicle;origin=@{name="Seoul";lat=37.5665;lon=126.978};destination=@{name="Incheon";lat=37.4563;lon=126.7052}} | ConvertTo-Json -Depth 4
  $created = Invoke-RestMethod http://localhost:8080/api/deliveries -Method Post -Headers @{"Idempotency-Key"="policy-$suffix"} -ContentType "application/json" -Body $body
  Start-Sleep -Seconds 2

  Save-Policy $vehicle 200000 150000 250000 200000 150000 250000 | Out-Null
  $event = @{eventId=[guid]::NewGuid().ToString();eventType="vehicle.telemetry.v1";occurredAt=(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ");traceId=[guid]::NewGuid().ToString();schemaVersion=1;payload=@{deliveryId=$created.id;vehicleId=$vehicle;lat=38.2;lon=127.8;progress=0.2;status="IN_TRANSIT";eta=(Get-Date).ToUniversalTime().AddHours(2).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")}}
  Send-Telemetry $event
  Start-Sleep -Seconds 3
  $suppressed = @((Invoke-RestMethod http://localhost:8080/api/alerts) | Where-Object {$_.deliveryId -eq $created.id})
  if ($suppressed.Count -ne 0) { throw "Vehicle override did not suppress alerts" }

  Save-Policy $vehicle 500 300 1500 600 300 1800 | Out-Null
  $event.eventId=[guid]::NewGuid().ToString();$event.traceId=[guid]::NewGuid().ToString()
  Send-Telemetry $event
  Start-Sleep -Seconds 3
  $active = @((Invoke-RestMethod http://localhost:8080/api/alerts) | Where-Object {$_.deliveryId -eq $created.id -and $_.status -eq "ACTIVE"})
  if ($active.Count -ne 2) { throw "Updated vehicle policy was not applied; active alerts=$($active.Count)" }
  if (($active | Where-Object {$_.thresholdValue -notin @(500,600)}).Count -ne 0) { throw "Alerts did not record the effective policy thresholds" }

  $policy = (Invoke-RestMethod http://localhost:8080/api/alert-policies) | Where-Object vehicleId -eq $vehicle
  $audits = @((Invoke-RestMethod http://localhost:8080/api/alert-policies/audits) | Where-Object vehicleId -eq $vehicle)
  if ($policy.updatedBy -ne "policy-smoke" -or $audits.Count -ne 2) { throw "Policy or immutable audit history was not persisted" }
  Write-Host "PASS: vehicle=$vehicle, high thresholds suppressed alerts, updated thresholds opened 2 alerts, audits=2"
}
finally {
  docker compose start simulator | Out-Null
}
