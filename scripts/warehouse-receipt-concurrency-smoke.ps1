$ErrorActionPreference="Stop"
$suffix=[guid]::NewGuid().ToString("N").Substring(0,8);$warehouse="WH-RECEIPT-$suffix";$sku="SKU-$suffix"
$jobs=1..2|ForEach-Object{Start-Job -ScriptBlock{param($warehouse,$sku,$suffix,$number)$body=@{referenceNumber="RCV-$suffix-$number";warehouseId=$warehouse;sku=$sku;quantity=5}|ConvertTo-Json;try{$value=Invoke-RestMethod http://localhost:8080/api/warehouse/receipts -Method Post -Headers @{"Idempotency-Key"="rcv-$suffix-$number"} -ContentType "application/json" -Body $body;[pscustomobject]@{ok=$true;id=$value.id}}catch{[pscustomobject]@{ok=$false;status=$_.Exception.Response.StatusCode.value__}}} -ArgumentList $warehouse,$sku,$suffix,$_}
$results=@($jobs|Wait-Job|Receive-Job);$jobs|Remove-Job
if(@($results|Where-Object{-not $_.ok}).Count-ne 0-or @($results.id|Select-Object -Unique).Count-ne 2){throw "Concurrent receipts did not both persist: $($results|ConvertTo-Json -Compress)"}
$stock=@((Invoke-RestMethod http://localhost:8080/api/warehouse/stock)|Where-Object{$_.warehouseId -eq $warehouse -and $_.sku -eq $sku})
$entries=@((Invoke-RestMethod http://localhost:8080/api/warehouse/ledger)|Where-Object{$_.warehouseId -eq $warehouse -and $_.sku -eq $sku -and $_.transactionType -eq "RECEIPT"})
if($stock.onHand -ne 10 -or $stock.reserved -ne 0 -or $entries.Count -ne 2){throw "Concurrent receipts were not summed exactly once: stock=$($stock|ConvertTo-Json -Compress) ledger=$($entries.Count)"}
Write-Host "PASS: warehouse=$warehouse sku=$sku, two concurrent receipts produced stock=10 and two ledger entries"
