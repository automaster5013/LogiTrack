$ErrorActionPreference = "Stop"

$trace = "replay-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
$poison = @{
  eventId = "not-a-uuid"
  eventType = "vehicle.telemetry.v1"
  occurredAt = (Get-Date).ToUniversalTime().ToString("o")
  traceId = $trace
  schemaVersion = 1
  payload = @{}
} | ConvertTo-Json -Compress
try {
$poison | docker compose exec -T kafka /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server kafka:29092 --topic vehicle.telemetry.v1

$started = Get-Date
$deadline = $started.AddSeconds(15)
do {
  Start-Sleep -Seconds 2
  $events = Invoke-RestMethod "http://localhost:8080/api/operations/dlq?status=PENDING"
  $event = $events.Where({$_.traceId -eq $trace}) | Select-Object -First 1
} while (-not $event -and (Get-Date) -lt $deadline)
if (-not $event) { throw "Poison event was not cataloged in the DLQ" }
$quarantineSeconds = ((Get-Date) - $started).TotalSeconds

$replayed = Invoke-RestMethod "http://localhost:8080/api/operations/dlq/$($event.id)/replay" -Method Post -Headers @{"X-Operator"="smoke-operator"}
if ($replayed.status -ne "REPLAYED") { throw "DLQ event was not marked replayed" }
$audits = Invoke-RestMethod "http://localhost:8080/api/operations/replay-audits"
$audit = $audits.Where({$_.deadLetterEventId -eq $event.id}) | Select-Object -First 1
if (-not $audit -or $audit.actor -ne "smoke-operator") { throw "Replay audit was not recorded" }

$repeated = Invoke-RestMethod "http://localhost:8080/api/operations/dlq/$($event.id)/replay" -Method Post -Headers @{"X-Operator"="smoke-operator"}
if ($repeated.status -ne "REPLAYED" -or $repeated.replayedBy -ne "smoke-operator") { throw "Identical replay retry did not return the stored result" }
$repeatedAudits = @((Invoke-RestMethod "http://localhost:8080/api/operations/replay-audits") | Where-Object {$_.deadLetterEventId -eq $event.id})
if ($repeatedAudits.Count -ne 1) { throw "Identical replay retry duplicated audit evidence" }

try {
  Invoke-RestMethod "http://localhost:8080/api/operations/dlq/$($event.id)/replay" -Method Post -Headers @{"X-Operator"="another-operator"}
  throw "Replay by a different operator unexpectedly succeeded"
} catch {
  if ($_.Exception.Response.StatusCode.value__ -ne 409) { throw }
}

$deadline = (Get-Date).AddSeconds(15)
do {
  Start-Sleep -Seconds 1
  $requeued = (docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT count(*) FROM dead_letter_events WHERE trace_id='$trace' AND status='PENDING'").Trim()
} while ([int]$requeued -lt 1 -and (Get-Date) -lt $deadline)
if ([int]$requeued -lt 1) { throw "Replayed poison event was not quarantined again" }
Write-Host "PASS: event=$($event.id), trace=$trace, quarantined=$([math]::Round($quarantineSeconds, 2))s, status=$($replayed.status), identical-retry=200, different-operator=409, audit=$($audit.id), requarantined=$requeued"
} finally {
  docker compose exec -T postgres psql -U logitrack -d logitrack -v ON_ERROR_STOP=1 -c "DELETE FROM dead_letter_events WHERE trace_id='$trace'" | Out-Null
}
