$ErrorActionPreference = "Stop"
$suffix=[guid]::NewGuid().ToString("N").Substring(0,8)
$warehouse="WH-CONCURRENT-$suffix";$sku="SKU-$suffix"
$receipt=@{referenceNumber="RCV-$suffix";warehouseId=$warehouse;sku=$sku;quantity=10}|ConvertTo-Json
$outbound=@{referenceNumber="OUT-$suffix";warehouseId=$warehouse;sku=$sku;quantity=2}|ConvertTo-Json
Invoke-RestMethod http://localhost:8080/api/warehouse/receipts -Method Post -Headers @{"Idempotency-Key"="rcv-$suffix"} -ContentType "application/json" -Body $receipt|Out-Null
$task=Invoke-RestMethod http://localhost:8080/api/warehouse/outbounds -Method Post -Headers @{"Idempotency-Key"="out-$suffix"} -ContentType "application/json" -Body $outbound
$jobs=1..2|ForEach-Object{Start-Job -ScriptBlock{param($id)try{$value=Invoke-RestMethod "http://localhost:8080/api/warehouse/outbounds/$id/dispatch" -Method Post;[pscustomobject]@{ok=$true;status=$value.status}}catch{[pscustomobject]@{ok=$false;status=$_.Exception.Response.StatusCode.value__}}} -ArgumentList $task.id}
$results=@($jobs|Wait-Job|Receive-Job);$jobs|Remove-Job
if(@($results|Where-Object{-not $_.ok}).Count-ne 0-or @($results|Where-Object{$_.status-ne "DISPATCHED"}).Count-ne 0){throw "Concurrent dispatch requests did not both resolve idempotently: $($results|ConvertTo-Json -Compress)"}
$stock=@((Invoke-RestMethod http://localhost:8080/api/warehouse/stock)|Where-Object{$_.warehouseId -eq $warehouse -and $_.sku -eq $sku})
$dispatchEntries=@((Invoke-RestMethod http://localhost:8080/api/warehouse/ledger)|Where-Object{$_.taskId -eq $task.id -and $_.transactionType -eq "DISPATCH"})
if($stock.onHand -ne 8 -or $stock.reserved -ne 0 -or $dispatchEntries.Count -ne 1){throw "Concurrent dispatch mutated stock more than once: onHand=$($stock.onHand) reserved=$($stock.reserved) ledger=$($dispatchEntries.Count)"}
Write-Host "PASS: task=$($task.id), concurrent dispatch returned DISPATCHED twice with one stock mutation and ledger entry"
