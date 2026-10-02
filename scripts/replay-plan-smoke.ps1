$ErrorActionPreference = "Stop"
$prefix = "batch-" + [guid]::NewGuid().ToString("N").Substring(0,8)
$first = [guid]::NewGuid().ToString()
$second = [guid]::NewGuid().ToString()
$offset = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

$insert = @"
INSERT INTO dead_letter_events(id,original_topic,message_key,payload,trace_id,exception_message,dlq_topic,dlq_partition,dlq_offset,status,failed_at) VALUES
('$first','delivery.created.v1','replay-plan-smoke-1','{}','$prefix-1','synthetic invalid event','vehicle.telemetry.dlq.v1',0,$offset,'PENDING',now()),
('$second','delivery.created.v1','replay-plan-smoke-2','{}','$prefix-2','synthetic invalid event','vehicle.telemetry.dlq.v1',0,$($offset+1),'PENDING',now());
"@
docker compose exec -T postgres psql -U logitrack -d logitrack -v ON_ERROR_STOP=1 -c $insert | Out-Null

$deadline=(Get-Date).AddSeconds(20)
do {
  Start-Sleep -Seconds 1
  $catalog=Invoke-RestMethod "http://localhost:8080/api/operations/dlq?status=PENDING"
  $selected=@($catalog.Where({$_.traceId -like "$prefix-*"}))
} while($selected.Count -lt 2 -and (Get-Date)-lt $deadline)
if($selected.Count -ne 2){throw "Expected two cataloged events, got $($selected.Count)"}

$body=@{eventIds=@($selected|ForEach-Object {$_.id})}|ConvertTo-Json
$requestKey=[guid]::NewGuid().ToString()
$plan=Invoke-RestMethod http://localhost:8080/api/operations/replay-plans -Method Post -Headers @{"X-Operator"="batch-smoke";"Idempotency-Key"=$requestKey} -ContentType "application/json" -Body $body
$repeatedPlan=Invoke-RestMethod http://localhost:8080/api/operations/replay-plans -Method Post -Headers @{"X-Operator"="batch-smoke";"Idempotency-Key"=$requestKey} -ContentType "application/json" -Body $body
if($repeatedPlan.id -ne $plan.id){throw "Repeated replay plan creation did not return the stored plan"}
if($plan.status -ne "PREPARED" -or $plan.eventIds.Count -ne 2){throw "Dry-run plan is invalid"}

$executionKey=[guid]::NewGuid().ToString()
$timer=[Diagnostics.Stopwatch]::StartNew()
$executed=Invoke-RestMethod "http://localhost:8080/api/operations/replay-plans/$($plan.id)/execute" -Method Post -Headers @{"X-Operator"="batch-smoke";"X-Replay-Approval"="APPROVE";"Idempotency-Key"=$executionKey}
$timer.Stop()
if($executed.status -ne "EXECUTED" -or $executed.succeededCount -ne 2){throw "Replay plan did not execute completely"}
if($timer.Elapsed.TotalMilliseconds -lt 150){throw "Configured replay rate limit was not applied"}
$repeated=Invoke-RestMethod "http://localhost:8080/api/operations/replay-plans/$($plan.id)/execute" -Method Post -Headers @{"X-Operator"="batch-smoke";"X-Replay-Approval"="APPROVE";"Idempotency-Key"=$executionKey}
if($repeated.status -ne "EXECUTED" -or $repeated.succeededCount -ne 2 -or $repeated.failedCount -ne 0){throw "Repeated replay execution did not return the stored result"}

$tooMany=@(1..21|ForEach-Object {[guid]::NewGuid().ToString()})
try {
  Invoke-RestMethod http://localhost:8080/api/operations/replay-plans -Method Post -Headers @{"X-Operator"="batch-smoke";"Idempotency-Key"=[guid]::NewGuid().ToString()} -ContentType "application/json" -Body (@{eventIds=$tooMany}|ConvertTo-Json)
  throw "Oversized replay plan unexpectedly succeeded"
} catch {
  if($_.Exception.Response.StatusCode.value__ -ne 400){throw}
}

Write-Host "PASS: plan=$($plan.id), events=2, status=$($executed.status), repeated=idempotent, elapsed=$([math]::Round($timer.Elapsed.TotalMilliseconds))ms, max-batch=20"
docker compose exec -T postgres psql -U logitrack -d logitrack -v ON_ERROR_STOP=1 -c "DELETE FROM dead_letter_events WHERE trace_id LIKE '$prefix-%'"|Out-Null
