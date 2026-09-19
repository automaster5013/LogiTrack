$ErrorActionPreference = "Stop"
$suffix=[guid]::NewGuid().ToString("N").Substring(0,8)
$key="idempotency-race-$suffix"
$body=@{orderNumber="ORD-RACE-$suffix";vehicleId="TRUCK-RACE";origin=@{name="Seoul";lat=37.5;lon=127};destination=@{name="Incheon";lat=37.4;lon=126.7}}|ConvertTo-Json -Depth 4 -Compress
$jobs=1..2|ForEach-Object { Start-Job -ScriptBlock { param($key,$body) try{$response=Invoke-RestMethod http://localhost:8080/api/deliveries -Method Post -Headers @{"Idempotency-Key"=$key} -ContentType application/json -Body $body;"201:$($response.id)"}catch{"$($_.Exception.Response.StatusCode.value__):error"} } -ArgumentList $key,$body }
try{$results=@($jobs|Wait-Job|Receive-Job)}finally{$jobs|Remove-Job -Force}
$ids=@($results|ForEach-Object {($_-split':',2)[1]}|Sort-Object -Unique)
if(@($results|Where-Object {$_-like'201:*'}).Count-ne2-or$ids.Count-ne1){throw "Expected two successful responses for one delivery, got $($results-join',')"}
$rows=(docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT count(*) FROM deliveries WHERE idempotency_key='$key'").Trim()
if($rows-ne"1"){throw "Expected one persisted delivery, got $rows"}
Write-Host "PASS: concurrent identical requests returned delivery=$($ids[0]), persisted rows=$rows"
