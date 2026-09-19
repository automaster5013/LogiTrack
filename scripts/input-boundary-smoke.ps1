$ErrorActionPreference = "Stop"
$tooLong="X"*161
$body=@{orderNumber="ORD-BOUNDARY";vehicleId="TRUCK-1";origin=@{name="Seoul";lat=37.5;lon=127};destination=@{name="Incheon";lat=37.4;lon=126.7}}|ConvertTo-Json -Depth 4
try{Invoke-WebRequest http://localhost:8080/api/deliveries -Method Post -Headers @{"Idempotency-Key"=$tooLong} -ContentType application/json -Body $body -UseBasicParsing|Out-Null;throw "Oversized idempotency key was accepted"}catch{if($_.Exception.Response.StatusCode.value__-ne 400){throw}}
$order=@{orderNumber=("O"*81);origin=@{name="Seoul";lat=37.5;lon=127};destination=@{name="Incheon";lat=37.4;lon=126.7}}|ConvertTo-Json -Depth 4
try{Invoke-WebRequest http://localhost:8080/api/orders -Method Post -Headers @{"Idempotency-Key"="boundary-order"} -ContentType application/json -Body $order -UseBasicParsing|Out-Null;throw "Oversized order number was accepted"}catch{if($_.Exception.Response.StatusCode.value__-ne 400){throw}}
Write-Host "PASS: oversized idempotency and domain fields return HTTP 400 before persistence"
