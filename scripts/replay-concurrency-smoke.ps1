$ErrorActionPreference = "Stop"
$eventId=[guid]::NewGuid().ToString()
$trace=[guid]::NewGuid().ToString()
$sql="INSERT INTO dead_letter_events (id,original_topic,message_key,payload,trace_id,exception_message,dlq_topic,dlq_partition,dlq_offset,status,failed_at) VALUES ('$eventId','replay-concurrency-smoke.v1','$eventId','{}','$trace','injected failure','vehicle.telemetry.dlq.v1',0,999999,'PENDING',now())"
docker compose exec -T postgres psql -U logitrack -d logitrack -v ON_ERROR_STOP=1 -c $sql|Out-Null
$jobs=1..2|ForEach-Object { Start-Job -ScriptBlock { param($id) try{Invoke-WebRequest "http://localhost:8080/api/operations/dlq/$id/replay" -Method Post -Headers @{"X-Operator"="concurrency-smoke"} -UseBasicParsing|Out-Null;200}catch{$_.Exception.Response.StatusCode.value__} } -ArgumentList $eventId }
try{$statuses=@($jobs|Wait-Job|Receive-Job)}finally{$jobs|Remove-Job -Force}
if(@($statuses|Where-Object {$_-eq 200}).Count-ne1-or@($statuses|Where-Object {$_-eq 409}).Count-ne1){throw "Expected one 200 and one 409, got $($statuses-join',')"}
$auditCount=(docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT count(*) FROM replay_audits WHERE dead_letter_event_id='$eventId'").Trim()
if($auditCount-ne"1"){throw "Expected one replay audit, got $auditCount"}
Write-Host "PASS: concurrent replay statuses=$($statuses-join','), audits=$auditCount"
