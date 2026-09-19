$ErrorActionPreference = "Stop"
$generated=Invoke-WebRequest http://localhost:8080/api/deliveries?limit=1 -UseBasicParsing
$generatedId=$generated.Headers["X-Trace-Id"]
if(!$generatedId-or$generatedId-notmatch '^[0-9a-f-]{36}$'){throw "API did not generate X-Trace-Id"}
$caller="support-case:$([guid]::NewGuid().ToString('N'))"
$preserved=Invoke-WebRequest http://localhost:8080/api/orders?limit=1 -Headers @{"X-Trace-Id"=$caller} -UseBasicParsing
if($preserved.Headers["X-Trace-Id"]-ne$caller){throw "API did not preserve caller X-Trace-Id"}
try{Invoke-WebRequest http://localhost:8080/api/orders -Headers @{"X-Trace-Id"="unsafe trace"} -UseBasicParsing|Out-Null;throw "Unsafe trace ID was accepted"}catch{if($_.Exception.Response.StatusCode.value__-ne 400){throw}}
Write-Host "PASS: generated=$generatedId, preserved=$caller, unsafe=400"
