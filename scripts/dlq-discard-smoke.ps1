$ErrorActionPreference = "Stop"

$eventId = [guid]::NewGuid().ToString()
$trace = "discard-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
$offset = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$reason = "confirmed invalid smoke fixture"

docker compose exec -T postgres psql -U logitrack -d logitrack -v ON_ERROR_STOP=1 -c "INSERT INTO dead_letter_events(id,original_topic,message_key,payload,trace_id,exception_message,dlq_topic,dlq_partition,dlq_offset,status,failed_at) VALUES ('$eventId','vehicle.telemetry.v1','discard-smoke','{}','$trace','synthetic invalid event','vehicle.telemetry.dlq.v1',0,$offset,'PENDING',now())" | Out-Null

try {
  $discarded = Invoke-RestMethod "http://localhost:8080/api/operations/dlq/$eventId/discard" -Method Post -ContentType "application/json" -Headers @{"X-Operator"="smoke-operator"} -Body (@{reason=$reason} | ConvertTo-Json -Compress)
  if ($discarded.status -ne "DISCARDED" -or $discarded.discardedBy -ne "smoke-operator" -or $discarded.discardReason -ne $reason -or -not $discarded.discardedAt) { throw "Discard disposition was incomplete" }

  $audits = Invoke-RestMethod "http://localhost:8080/api/operations/replay-audits"
  $audit = $audits.Where({$_.deadLetterEventId -eq $eventId}) | Select-Object -First 1
  if (-not $audit -or $audit.action -ne "DISCARD" -or $audit.actor -ne "smoke-operator" -or $audit.reason -ne $reason) { throw "Discard audit was not recorded" }

  try {
    Invoke-RestMethod "http://localhost:8080/api/operations/dlq/$eventId/discard" -Method Post -ContentType "application/json" -Headers @{"X-Operator"="smoke-operator"} -Body (@{reason="duplicate"} | ConvertTo-Json -Compress)
    throw "Duplicate discard unexpectedly succeeded"
  } catch {
    if ($_.Exception.Response.StatusCode.value__ -ne 409) { throw }
  }

  Write-Host "PASS: event=$eventId, trace=$trace, status=$($discarded.status), audit=$($audit.id), duplicate=409"
} finally {
  docker compose exec -T postgres psql -U logitrack -d logitrack -v ON_ERROR_STOP=1 -c "DELETE FROM dead_letter_events WHERE id='$eventId'" | Out-Null
}
