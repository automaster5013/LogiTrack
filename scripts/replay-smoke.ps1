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

try {
  Invoke-RestMethod "http://localhost:8080/api/operations/dlq/$($event.id)/replay" -Method Post -Headers @{"X-Operator"="smoke-operator"}
  throw "Duplicate replay unexpectedly succeeded"
} catch {
  if ($_.Exception.Response.StatusCode.value__ -ne 409) { throw }
}

Write-Host "PASS: event=$($event.id), trace=$trace, quarantined=$([math]::Round($quarantineSeconds, 2))s, status=$($replayed.status), audit=$($audit.id), duplicate=409"
