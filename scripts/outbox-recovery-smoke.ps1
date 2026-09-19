$ErrorActionPreference = "Stop"
$eventId=[guid]::NewGuid().ToString()
$aggregateId=[guid]::NewGuid().ToString()
$sql="INSERT INTO outbox_events (id,aggregate_type,aggregate_id,event_type,topic,event_key,payload,status,attempts,last_error,created_at) VALUES ('$eventId','SMOKE','$aggregateId','outbox.recovery.smoke.v1','outbox-retry-smoke.v1','$aggregateId','{}','FAILED',20,'injected failure',now())"
docker compose exec -T postgres psql -U logitrack -d logitrack -v ON_ERROR_STOP=1 -c $sql | Out-Null
$failures=@(Invoke-RestMethod http://localhost:8080/api/operations/outbox/failures)
$failure=$failures|Where-Object { $_.id -eq $eventId }
if(!$failure-or$failure.attempts-ne 20-or$failure.lastError-ne "injected failure"){throw "Injected outbox failure was not listed"}
$retry=Invoke-RestMethod "http://localhost:8080/api/operations/outbox/failures/$eventId/retry" -Method Post -Headers @{"X-Operator"="outbox-smoke"}
if($retry.status-ne "PENDING"-or$retry.attempts-ne 0){throw "Outbox failure was not reset to PENDING"}
$deadline=(Get-Date).AddSeconds(30)
do{Start-Sleep -Seconds 1;$status=(docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT status FROM outbox_events WHERE id='$eventId'").Trim()}while($status-ne"PUBLISHED"-and(Get-Date)-lt$deadline)
if($status-ne"PUBLISHED"){throw "Retried outbox event was not published"}
$audit=(docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT actor FROM outbox_retry_audits WHERE outbox_event_id='$eventId'").Trim()
if($audit-ne"outbox-smoke"){throw "Outbox retry audit was not recorded"}
Write-Host "PASS: event=$eventId, status=$status, actor=$audit"
