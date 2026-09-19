$ErrorActionPreference = "Stop"
foreach($path in @("deliveries","orders","routes","alerts","warehouse/stock","warehouse/tasks")){
  $response=Invoke-WebRequest "http://localhost:8080/api/$path`?limit=1" -UseBasicParsing
  $items=@($response.Content|ConvertFrom-Json)
  if($items.Count-gt 1){throw "$path returned more rows than requested"}
  try{Invoke-WebRequest "http://localhost:8080/api/$path`?limit=501" -UseBasicParsing|Out-Null;throw "$path accepted limit=501"}catch{
    if($_.Exception.Response.StatusCode.value__-ne 400){throw}
  }
}
Write-Host "PASS: delivery, order, route, alert, stock, and warehouse task lists enforce limit=1..500"
