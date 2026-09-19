$ErrorActionPreference = "Stop"
$suffix=[guid]::NewGuid().ToString("N").Substring(0,8)
$orderNumber="ORD-CONFLICT-$suffix"
$body=@{orderNumber=$orderNumber;origin=@{name="Seoul";lat=37.5;lon=127};destination=@{name="Incheon";lat=37.4;lon=126.7}}|ConvertTo-Json -Depth 4
Invoke-WebRequest http://localhost:8080/api/orders -Method Post -Headers @{"Idempotency-Key"="conflict-a-$suffix"} -ContentType application/json -Body $body -UseBasicParsing|Out-Null
try{Invoke-WebRequest http://localhost:8080/api/orders -Method Post -Headers @{"Idempotency-Key"="conflict-b-$suffix";"X-Trace-Id"="conflict-trace-$suffix"} -ContentType application/json -Body $body -UseBasicParsing|Out-Null;throw "Duplicate order number was accepted"}catch{
  if($_.Exception.Response.StatusCode.value__-ne 409){throw}
  $error=$_.ErrorDetails.Message|ConvertFrom-Json
  if($error.error-ne"Resource conflicts with existing data"-or$error.traceId-ne"conflict-trace-$suffix"-or!$error.timestamp){throw "Unexpected conflict error contract"}
}
try{Invoke-WebRequest http://localhost:8080/api/orders -Method Post -Headers @{"Idempotency-Key"="malformed-$suffix"} -ContentType application/json -Body '{' -UseBasicParsing|Out-Null;throw "Malformed JSON was accepted"}catch{
  if($_.Exception.Response.StatusCode.value__-ne 400){throw}
  if(($_.ErrorDetails.Message|ConvertFrom-Json).error-ne"Malformed request body"){throw "Unexpected malformed JSON error"}
}
foreach($case in @(
  @{url="http://localhost:8080/api/alert-policies";headers=@{"X-Operator"="boundary-smoke"};body='null'},
  @{url="http://localhost:8080/api/operations/replay-plans";headers=@{"X-Operator"="boundary-smoke"};body='{"eventIds":[null]}'}
)){
  try{Invoke-WebRequest $case.url -Method Post -Headers $case.headers -ContentType application/json -Body $case.body -UseBasicParsing|Out-Null;throw "Invalid null request was accepted: $($case.url)"}catch{
    if($_.Exception.Response.StatusCode.value__-ne 400){throw}
    $error=$_.ErrorDetails.Message|ConvertFrom-Json
    if(!$error.error-or!$error.traceId-or!$error.timestamp){throw "Null request did not return the standard error contract: $($case.url)"}
  }
}
Write-Host "PASS: duplicate=409 safe contract, malformed/null inputs=400, trace correlation preserved"
