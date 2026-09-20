$ErrorActionPreference = "Stop"
$oldProcessed=[guid]::NewGuid().ToString();$recentProcessed=[guid]::NewGuid().ToString()
$oldOutbox=[guid]::NewGuid().ToString();$recentOutbox=[guid]::NewGuid().ToString();$aggregate=[guid]::NewGuid().ToString()
$oldOutboxAudit=[guid]::NewGuid().ToString()
$oldTelemetry=[guid]::NewGuid().ToString();$recentTelemetry=[guid]::NewGuid().ToString()
$oldDlq=[guid]::NewGuid().ToString();$recentDlq=[guid]::NewGuid().ToString();$oldDiscardedDlq=[guid]::NewGuid().ToString();$recentDiscardedDlq=[guid]::NewGuid().ToString();$oldReplayAudit=[guid]::NewGuid().ToString()
$offsetBase=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
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
INSERT INTO outbox_retry_audits(id,outbox_event_id,actor,occurred_at) VALUES
('$oldOutboxAudit','$oldOutbox','retention-smoke',now()-interval '8 days');
INSERT INTO telemetry_points(event_id,delivery_id,vehicle_id,latitude,longitude,progress,occurred_at) VALUES
('$oldTelemetry','$deliveryId','$vehicleSql',37.5,127.0,0.5,now()-interval '31 days'),
('$recentTelemetry','$deliveryId','$vehicleSql',37.5,127.0,0.5,now());
INSERT INTO dead_letter_events(id,original_topic,message_key,payload,trace_id,exception_message,dlq_topic,dlq_partition,dlq_offset,status,failed_at,replayed_at,replayed_by) VALUES
('$oldDlq','vehicle.telemetry.v1','old','{}',null,'smoke','vehicle.telemetry.dlq.v1',0,$offsetBase,'REPLAYED',now()-interval '91 days',now()-interval '91 days','retention-smoke'),
('$recentDlq','vehicle.telemetry.v1','recent','{}',null,'smoke','vehicle.telemetry.dlq.v1',0,$($offsetBase+1),'REPLAYED',now(),now(),'retention-smoke');
INSERT INTO dead_letter_events(id,original_topic,message_key,payload,trace_id,exception_message,dlq_topic,dlq_partition,dlq_offset,status,failed_at,discarded_at,discarded_by,discard_reason) VALUES
('$oldDiscardedDlq','vehicle.telemetry.v1','old-discarded','{}',null,'smoke','vehicle.telemetry.dlq.v1',0,$($offsetBase+2),'DISCARDED',now()-interval '91 days',now()-interval '91 days','retention-smoke','expired fixture'),
('$recentDiscardedDlq','vehicle.telemetry.v1','recent-discarded','{}',null,'smoke','vehicle.telemetry.dlq.v1',0,$($offsetBase+3),'DISCARDED',now(),now(),'retention-smoke','recent fixture');
INSERT INTO replay_audits(id,dead_letter_event_id,action,actor,occurred_at) VALUES
('$oldReplayAudit','$oldDlq','REPLAY','retention-smoke',now()-interval '91 days');
"@
$allIds=@($oldProcessed,$recentProcessed,$oldOutbox,$recentOutbox,$oldTelemetry,$recentTelemetry)
try {
  docker compose exec -T postgres psql -U logitrack -d logitrack -v ON_ERROR_STOP=1 -c $insert | Out-Null
  docker compose restart api | Out-Null
  if($LASTEXITCODE-ne0){throw "Could not restart API to trigger a deterministic retention cycle"}
  $deadline=(Get-Date).AddSeconds(120)
  do {
    Start-Sleep -Seconds 3
    $oldCount=(docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT (SELECT count(*) FROM processed_events WHERE event_id='$oldProcessed')+(SELECT count(*) FROM outbox_events WHERE id='$oldOutbox')+(SELECT count(*) FROM outbox_retry_audits WHERE id='$oldOutboxAudit')+(SELECT count(*) FROM telemetry_points WHERE event_id='$oldTelemetry')+(SELECT count(*) FROM dead_letter_events WHERE id IN ('$oldDlq','$oldDiscardedDlq'))+(SELECT count(*) FROM replay_audits WHERE id='$oldReplayAudit')").Trim()
  } while($oldCount-ne'0'-and(Get-Date)-lt$deadline)
  if($oldCount-ne'0'){throw "Retention cleanup did not remove all expired rows; remaining=$oldCount"}
  $recentCount=(docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT (SELECT count(*) FROM processed_events WHERE event_id='$recentProcessed')+(SELECT count(*) FROM outbox_events WHERE id='$recentOutbox')+(SELECT count(*) FROM telemetry_points WHERE event_id='$recentTelemetry')").Trim()
  $recentCount=[int]$recentCount+[int](docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT count(*) FROM dead_letter_events WHERE id IN ('$recentDlq','$recentDiscardedDlq')").Trim()
  if($recentCount-ne'5'){throw "Retention cleanup removed recent rows; remaining=$recentCount"}
  $metrics=(Invoke-WebRequest http://localhost:8080/actuator/prometheus -UseBasicParsing).Content
  if($metrics-notmatch'logitrack_retention_deleted_total'){throw "Retention deletion metric is missing"}
  Write-Host "PASS: expired processed/outbox/audit/telemetry/replayed+discarded DLQ rows deleted, 5 recent rows retained, metrics exposed"
} finally {
  docker compose exec -T postgres psql -U logitrack -d logitrack -c "DELETE FROM processed_events WHERE event_id IN ('$oldProcessed','$recentProcessed');DELETE FROM outbox_events WHERE id IN ('$oldOutbox','$recentOutbox');DELETE FROM telemetry_points WHERE event_id IN ('$oldTelemetry','$recentTelemetry');DELETE FROM dead_letter_events WHERE id IN ('$oldDlq','$recentDlq','$oldDiscardedDlq','$recentDiscardedDlq');" | Out-Null
}
