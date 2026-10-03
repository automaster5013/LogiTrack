$ErrorActionPreference="Stop"
$suffix=[guid]::NewGuid().ToString("N")
$warehouse="WH-LEGACY-$suffix"
$sku="SKU-LEGACY-$suffix"
$receipt=@{referenceNumber="RCV-LEGACY-$suffix";warehouseId=$warehouse;sku=$sku;quantity=5}|ConvertTo-Json
$outbound=@{referenceNumber="OUT-LEGACY-$suffix";warehouseId=$warehouse;sku=$sku;quantity=4}|ConvertTo-Json

Invoke-RestMethod http://localhost:8080/api/warehouse/receipts -Method Post -Headers @{"Idempotency-Key"="receipt-$suffix"} -ContentType application/json -Body $receipt|Out-Null
$task=Invoke-RestMethod http://localhost:8080/api/warehouse/outbounds -Method Post -Headers @{"Idempotency-Key"="pick-$suffix"} -ContentType application/json -Body $outbound
Invoke-RestMethod "http://localhost:8080/api/warehouse/outbounds/$($task.id)/dispatch" -Method Post -Headers @{"Idempotency-Key"="original-$suffix"}|Out-Null

docker compose exec -T postgres psql -U logitrack -d logitrack -v ON_ERROR_STOP=1 -c "UPDATE warehouse_tasks SET dispatch_request_key=NULL WHERE id='$($task.id)'"|Out-Null
$retryKey="claimed-$suffix"
$first=Invoke-RestMethod "http://localhost:8080/api/warehouse/outbounds/$($task.id)/dispatch" -Method Post -Headers @{"Idempotency-Key"=$retryKey}
$repeated=Invoke-RestMethod "http://localhost:8080/api/warehouse/outbounds/$($task.id)/dispatch" -Method Post -Headers @{"Idempotency-Key"=$retryKey}
if($first.id-ne$task.id-or$repeated.id-ne$task.id-or$first.status-ne"DISPATCHED"){throw "Legacy dispatch retry did not return the existing task"}

$conflict=Invoke-WebRequest "http://localhost:8080/api/warehouse/outbounds/$($task.id)/dispatch" -Method Post -Headers @{"Idempotency-Key"="different-$suffix"} -SkipHttpErrorCheck
if($conflict.StatusCode-ne409){throw "A different key reclaimed the legacy dispatch: HTTP $($conflict.StatusCode)"}
$facts=(docker compose exec -T postgres psql -U logitrack -d logitrack -AtF '|' -c "SELECT dispatch_request_key,(SELECT count(*) FROM inventory_ledger WHERE task_id='$($task.id)' AND transaction_type='DISPATCH'),(SELECT count(*) FROM outbox_events WHERE aggregate_id='$($task.id)' AND event_type='warehouse.outbound.dispatched.v1') FROM warehouse_tasks WHERE id='$($task.id)'").Trim()
if($facts-ne"$retryKey|1|1"){throw "Unexpected persisted legacy dispatch facts: $facts"}

Write-Host "PASS: legacy warehouse dispatch claimed one key without duplicate ledger or outbox effects"
