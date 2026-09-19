$ErrorActionPreference = "Stop"
$oldProcessed=[guid]::NewGuid().ToString();$recentProcessed=[guid]::NewGuid().ToString()
$oldOutbox=[guid]::NewGuid().ToString();$recentOutbox=[guid]::NewGuid().ToString();$aggregate=[guid]::NewGuid().ToString()
$oldTelemetry=[guid]::NewGuid().ToString();$recentTelemetry=[guid]::NewGuid().ToString()
$delivery=(docker compose exec -T postgres psql -U logitrack -d logitrack -tA -F '|' -c "SELECT id,vehicle_id FROM deliveries ORDER BY created_at LIMIT 1").Trim()
if(!$delivery){throw "A delivery is required for the retention smoke test"}
$deliveryId,$vehicleId=$delivery.Split('|',2)
$vehicleSql=$vehicleId.Replace("'","''")
$insert=@"
INSERT INTO processed_events(event_id,consumer_name,processed_at) VALUES
('$oldProcessed','retention-smoke',now()-interval '31 days'),('$recentProcessed','retention-smoke',now());
INSERT INTO outbox_events(id,aggregate_type,aggregate_id,event_type,topic,event_key,payload,status,attempts,created_at,published_at,next_attempt_at) VALUES
('$oldOutbox','SMOKE','$aggregate','retention.smoke.v1','retention.smoke.v1','$aggregate','{}','PUBLISHED',0,now()-interval '8 days',now()-interval '8 days',now()-interval '8 days'),
('$recentOutbox','SMOKE','$aggregate','retention.smoke.v1','retention.smoke.v1','$aggregate','{}','PUBLISHED',0,now(),now(),now());
INSERT INTO telemetry_points(event_id,delivery_id,vehicle_id,latitude,longitude,progress,occurred_at) VALUES
('$oldTelemetry','$deliveryId','$vehicleSql',37.5,127.0,0.5,now()-interval '31 days'),
('$recentTelemetry','$deliveryId','$vehicleSql',37.5,127.0,0.5,now());
"@
$allIds=@($oldProcessed,$recentProcessed,$oldOutbox,$recentOutbox,$oldTelemetry,$recentTelemetry)
try {
  docker compose exec -T postgres psql -U logitrack -d logitrack -v ON_ERROR_STOP=1 -c $insert | Out-Null
  $deadline=(Get-Date).AddSeconds(90)
  do {
    Start-Sleep -Seconds 3
    $oldCount=(docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT (SELECT count(*) FROM processed_events WHERE event_id='$oldProcessed')+(SELECT count(*) FROM outbox_events WHERE id='$oldOutbox')+(SELECT count(*) FROM telemetry_points WHERE event_id='$oldTelemetry')").Trim()
  } while($oldCount-ne'0'-and(Get-Date)-lt$deadline)
  if($oldCount-ne'0'){throw "Retention cleanup did not remove all expired rows; remaining=$oldCount"}
  $recentCount=(docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT (SELECT count(*) FROM processed_events WHERE event_id='$recentProcessed')+(SELECT count(*) FROM outbox_events WHERE id='$recentOutbox')+(SELECT count(*) FROM telemetry_points WHERE event_id='$recentTelemetry')").Trim()
  if($recentCount-ne'3'){throw "Retention cleanup removed recent rows; remaining=$recentCount"}
  $metrics=(Invoke-WebRequest http://localhost:8080/actuator/prometheus -UseBasicParsing).Content
  if($metrics-notmatch'logitrack_retention_deleted_total'){throw "Retention deletion metric is missing"}
  Write-Host "PASS: expired processed/outbox/telemetry rows deleted, 3 recent rows retained, metrics exposed"
} finally {
  docker compose exec -T postgres psql -U logitrack -d logitrack -c "DELETE FROM processed_events WHERE event_id IN ('$oldProcessed','$recentProcessed');DELETE FROM outbox_events WHERE id IN ('$oldOutbox','$recentOutbox');DELETE FROM telemetry_points WHERE event_id IN ('$oldTelemetry','$recentTelemetry');" | Out-Null
}
