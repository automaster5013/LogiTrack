$ErrorActionPreference = "Stop"
$suffix = [guid]::NewGuid().ToString("N").Substring(0,8)
$warehouse = "WH-SMOKE-$suffix"
$sku = "SKU-SMOKE"
$headers = @{"Idempotency-Key"="receipt-$suffix"}
$receiptBody = @{referenceNumber="ASN-$suffix";warehouseId=$warehouse;sku=$sku;quantity=10} | ConvertTo-Json
$receipt = Invoke-RestMethod http://localhost:8080/api/warehouse/receipts -Method Post -Headers $headers -ContentType "application/json" -Body $receiptBody
$duplicate = Invoke-RestMethod http://localhost:8080/api/warehouse/receipts -Method Post -Headers $headers -ContentType "application/json" -Body $receiptBody
if ($receipt.id -ne $duplicate.id) { throw "Receipt idempotency failed" }
$pickBody = @{referenceNumber="OUT-$suffix";warehouseId=$warehouse;sku=$sku;quantity=4} | ConvertTo-Json
$pick = Invoke-RestMethod http://localhost:8080/api/warehouse/outbounds -Method Post -Headers @{"Idempotency-Key"="pick-$suffix"} -ContentType "application/json" -Body $pickBody
$dispatch = Invoke-RestMethod "http://localhost:8080/api/warehouse/outbounds/$($pick.id)/dispatch" -Method Post
$dispatchAgain = Invoke-RestMethod "http://localhost:8080/api/warehouse/outbounds/$($pick.id)/dispatch" -Method Post
if ($dispatch.status -ne "DISPATCHED" -or $dispatchAgain.status -ne "DISPATCHED") { throw "Dispatch idempotency failed" }
$stock = (Invoke-RestMethod http://localhost:8080/api/warehouse/stock) | Where-Object {$_.warehouseId -eq $warehouse -and $_.sku -eq $sku}
if ($stock.onHand -ne 6 -or $stock.reserved -ne 0 -or $stock.available -ne 6) { throw "Unexpected stock: $($stock | ConvertTo-Json -Compress)" }
$entries = (Invoke-RestMethod http://localhost:8080/api/warehouse/ledger) | Where-Object {$_.warehouseId -eq $warehouse}
if ($entries.Count -ne 3) { throw "Expected three ledger entries, got $($entries.Count)" }
$rejectBody = @{referenceNumber="OUT-REJECT-$suffix";warehouseId=$warehouse;sku=$sku;quantity=999} | ConvertTo-Json
$rejected = Invoke-WebRequest http://localhost:8080/api/warehouse/outbounds -Method Post -Headers @{"Idempotency-Key"="reject-$suffix"} -ContentType "application/json" -Body $rejectBody -SkipHttpErrorCheck
if ($rejected.StatusCode -ne 409) { throw "Insufficient stock should return 409, got $($rejected.StatusCode)" }
$oversizedBody = @{referenceNumber="OUT-OVERSIZED-$suffix";warehouseId=$warehouse;sku=$sku;quantity=1000001} | ConvertTo-Json
$oversized = Invoke-WebRequest http://localhost:8080/api/warehouse/outbounds -Method Post -Headers @{"Idempotency-Key"="out-oversized-$suffix"} -ContentType "application/json" -Body $oversizedBody -SkipHttpErrorCheck
if ($oversized.StatusCode -ne 400) { throw "Oversized warehouse quantity should return 400, got $($oversized.StatusCode)" }
Start-Sleep -Milliseconds 700
$published = docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT count(*) FROM outbox_events WHERE aggregate_id IN ('$($receipt.id)','$($pick.id)') AND status='PUBLISHED'"
if ([int]$published.Trim() -ne 3) { throw "Expected three published warehouse events, got $published" }
Write-Host "PASS: warehouse=$warehouse, receipt=10, picked/dispatched=4, available=6, ledger=3, events=3"
