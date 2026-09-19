$ErrorActionPreference = "Stop"
$suffix=[guid]::NewGuid().ToString("N").Substring(0,8)
$key="idempotency-conflict-$suffix"
$body=@{orderNumber="ORD-IDEMP-$suffix";vehicleId="TRUCK-A";origin=@{name="Seoul";lat=37.5;lon=127};destination=@{name="Incheon";lat=37.4;lon=126.7}}
$first=Invoke-RestMethod http://localhost:8080/api/deliveries -Method Post -Headers @{"Idempotency-Key"=$key} -ContentType application/json -Body ($body|ConvertTo-Json -Depth 4)
$same=Invoke-RestMethod http://localhost:8080/api/deliveries -Method Post -Headers @{"Idempotency-Key"=$key} -ContentType application/json -Body ($body|ConvertTo-Json -Depth 4)
if($first.id-ne$same.id){throw "Identical idempotent request returned a different delivery"}
$body.vehicleId="TRUCK-B"
try{Invoke-WebRequest http://localhost:8080/api/deliveries -Method Post -Headers @{"Idempotency-Key"=$key} -ContentType application/json -Body ($body|ConvertTo-Json -Depth 4) -UseBasicParsing|Out-Null;throw "Different request reused idempotency key"}catch{if($_.Exception.Response.StatusCode.value__-ne 409){throw}}
Write-Host "PASS: identical request reused delivery=$($first.id), changed request=409"
