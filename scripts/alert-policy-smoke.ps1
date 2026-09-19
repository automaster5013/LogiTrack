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

  Invoke-RestMethod "http://localhost:8080/api/alert-policies/$vehicle" -Method Delete -Headers @{"X-Operator"="policy-smoke"} | Out-Null
  $event.eventId=[guid]::NewGuid().ToString();$event.traceId=[guid]::NewGuid().ToString()
  Send-Telemetry $event
  Start-Sleep -Seconds 3
  $active = @((Invoke-RestMethod http://localhost:8080/api/alerts) | Where-Object {$_.deliveryId -eq $created.id -and $_.status -eq "ACTIVE"})
  if ($active.Count -ne 2) { throw "Global policy was not applied after reset; active alerts=$($active.Count)" }
  if (($active | Where-Object {$_.thresholdValue -notin @(500,600)}).Count -ne 0) { throw "Alerts did not record the effective policy thresholds" }

  $policy = (Invoke-RestMethod http://localhost:8080/api/alert-policies) | Where-Object vehicleId -eq $vehicle
  $audits = @((Invoke-RestMethod http://localhost:8080/api/alert-policies/audits) | Where-Object vehicleId -eq $vehicle)
  if ($policy) { throw "Reset vehicle policy remained active" }
  if ($audits.Count -ne 2 -or @($audits | Where-Object action -eq "RESET").Count -ne 1) { throw "Policy reset audit history was not persisted" }

  $normal = @{eventId=[guid]::NewGuid().ToString();eventType="vehicle.telemetry.v1";occurredAt=(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ");traceId=[guid]::NewGuid().ToString();schemaVersion=1;payload=@{deliveryId=$created.id;vehicleId=$vehicle;lat=37.5665;lon=126.978;progress=0.3;status="IN_TRANSIT";eta=(Get-Date).ToUniversalTime().AddMinutes(1).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")}}
  Send-Telemetry $normal
  Start-Sleep -Seconds 3
  $stillActive = @((Invoke-RestMethod http://localhost:8080/api/alerts) | Where-Object {$_.deliveryId -eq $created.id -and $_.status -eq "ACTIVE"})
  if ($stillActive.Count -ne 0) { throw "Normal telemetry did not resolve alerts before restore" }

  $upsertAudit = @($audits | Where-Object action -eq "UPSERT")[0]
  if (-not $upsertAudit) { throw "Original policy snapshot was not found" }
  $restored = Invoke-RestMethod "http://localhost:8080/api/alert-policies/audits/$($upsertAudit.id)/restore" -Method Post -Headers @{"X-Operator"="policy-smoke"}
  if ($restored.vehicleId -ne $vehicle -or $restored.deviationOpenMeters -ne 200000 -or $restored.delayOpenSeconds -ne 200000) { throw "Restored policy did not match the audited snapshot" }

  $event.eventId=[guid]::NewGuid().ToString();$event.traceId=[guid]::NewGuid().ToString();$event.occurredAt=(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
  Send-Telemetry $event
  Start-Sleep -Seconds 3
  $afterRestore = @((Invoke-RestMethod http://localhost:8080/api/alerts) | Where-Object {$_.deliveryId -eq $created.id -and $_.status -eq "ACTIVE"})
  if ($afterRestore.Count -ne 0) { throw "Restored vehicle policy did not suppress alerts" }
  $audits = @((Invoke-RestMethod http://localhost:8080/api/alert-policies/audits) | Where-Object vehicleId -eq $vehicle)
  if ($audits.Count -ne 3 -or @($audits | Where-Object action -eq "RESTORE").Count -ne 1) { throw "Policy restore audit history was not persisted" }
  Write-Host "PASS: vehicle=$vehicle, override/reset/restore behavior verified, audits=3"
}
finally {
  docker compose start simulator | Out-Null
}
