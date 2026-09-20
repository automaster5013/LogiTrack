$ErrorActionPreference = "Stop"

$prefix = "discard-batch-" + [guid]::NewGuid().ToString("N").Substring(0,8)
$first = [guid]::NewGuid().ToString()
$second = [guid]::NewGuid().ToString()
$offset = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$reason = "confirmed invalid batch smoke fixtures"
$plan = $null

$insert = @"
INSERT INTO dead_letter_events(id,original_topic,message_key,payload,trace_id,exception_message,dlq_topic,dlq_partition,dlq_offset,status,failed_at) VALUES
('$first','vehicle.telemetry.v1','discard-batch-1','{}','$prefix-1','synthetic invalid event','vehicle.telemetry.dlq.v1',0,$offset,'PENDING',now()),
('$second','vehicle.telemetry.v1','discard-batch-2','{}','$prefix-2','synthetic invalid event','vehicle.telemetry.dlq.v1',0,$($offset+1),'PENDING',now());
"@
docker compose exec -T postgres psql -U logitrack -d logitrack -v ON_ERROR_STOP=1 -c $insert | Out-Null

try {
  $body = @{eventIds=@($first,$second,$first);reason=$reason} | ConvertTo-Json
  $plan = Invoke-RestMethod http://localhost:8080/api/operations/discard-plans -Method Post -Headers @{"X-Operator"="batch-smoke"} -ContentType "application/json" -Body $body
  if ($plan.status -ne "PREPARED" -or $plan.eventIds.Count -ne 2 -or $plan.reason -ne $reason) { throw "Discard dry-run plan is invalid" }

  try {
    Invoke-RestMethod "http://localhost:8080/api/operations/discard-plans/$($plan.id)/execute" -Method Post -Headers @{"X-Operator"="batch-smoke";"X-Discard-Approval"="APPROVE"}
    throw "Discard plan accepted an invalid approval"
  } catch {
    if ($_.Exception.Response.StatusCode.value__ -ne 400) { throw }
  }

  $executed = Invoke-RestMethod "http://localhost:8080/api/operations/discard-plans/$($plan.id)/execute" -Method Post -Headers @{"X-Operator"="batch-smoke";"X-Discard-Approval"="DISCARD"}
  if ($executed.status -ne "EXECUTED" -or $executed.succeededCount -ne 2 -or $executed.failedCount -ne 0) { throw "Discard plan did not execute completely" }

  $discarded = @((Invoke-RestMethod "http://localhost:8080/api/operations/dlq?status=DISCARDED") | Where-Object {$_.traceId -like "$prefix-*"})
  $audits = @((Invoke-RestMethod http://localhost:8080/api/operations/replay-audits) | Where-Object {@($first,$second) -contains $_.deadLetterEventId.ToString() -and $_.action -eq "DISCARD"})
  $wrongReasons = @($audits.Where({$_.reason -ne $reason}))
  if ($discarded.Count -ne 2 -or $audits.Count -ne 2 -or $wrongReasons.Count -ne 0) { throw "Discarded events or audits are incomplete: discarded=$($discarded.Count), audits=$($audits.Count), wrongReasons=$($wrongReasons.Count)" }

  try {
    Invoke-RestMethod "http://localhost:8080/api/operations/discard-plans/$($plan.id)/execute" -Method Post -Headers @{"X-Operator"="batch-smoke";"X-Discard-Approval"="DISCARD"}
    throw "Duplicate discard plan execution unexpectedly succeeded"
  } catch {
    if ($_.Exception.Response.StatusCode.value__ -ne 409) { throw }
  }

  Write-Host "PASS: plan=$($plan.id), unique-events=2, status=$($executed.status), audits=2, duplicate=409"
} finally {
  $cleanup = "DELETE FROM dead_letter_events WHERE trace_id LIKE '$prefix-%';"
  if ($plan) { $cleanup += "DELETE FROM discard_plans WHERE id='$($plan.id)';" }
  docker compose exec -T postgres psql -U logitrack -d logitrack -v ON_ERROR_STOP=1 -c $cleanup | Out-Null
}
