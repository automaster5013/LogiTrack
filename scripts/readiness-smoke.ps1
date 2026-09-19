$ErrorActionPreference = "Stop"
function Status-Code {
  return [int](curl.exe -sS -o NUL -w "%{http_code}" http://localhost:8080/actuator/health/readiness)
}
function Liveness-Code {
  return [int](curl.exe -sS -o NUL -w "%{http_code}" http://localhost:8080/actuator/health/liveness)
}
function Wait-Code([int]$expected,[int]$seconds=60) {
  $deadline=(Get-Date).AddSeconds($seconds)
  do {
    $code=Status-Code
    if($code -eq $expected){return}
    Start-Sleep -Seconds 2
  } while((Get-Date) -lt $deadline)
  throw "Readiness did not reach HTTP $expected; last status was $code"
}
$redisStopped=$false
$postgresStopped=$false
try {
  Wait-Code 200
  docker compose stop redis | Out-Null
  $redisStopped=$true
  Wait-Code 200 20
  docker compose start redis | Out-Null
  $redisStopped=$false
  docker compose stop postgres | Out-Null
  $postgresStopped=$true
  $failureTimer=[Diagnostics.Stopwatch]::StartNew()
  $failedReadiness=Status-Code
  $failureTimer.Stop()
  if($failedReadiness -ne 503){Wait-Code 503}
  if($failureTimer.Elapsed.TotalSeconds -gt 6){throw "PostgreSQL outage readiness took $([math]::Round($failureTimer.Elapsed.TotalSeconds,2))s; expected at most 6s"}
  if((Liveness-Code) -ne 200){throw "PostgreSQL outage incorrectly failed process liveness"}
  docker compose start postgres | Out-Null
  $postgresStopped=$false
  Wait-Code 200 90
  Write-Host "PASS: redis outage stayed ready, postgres outage returned readiness 503 in $([math]::Round($failureTimer.Elapsed.TotalSeconds,2))s with liveness 200, recovery returned 200"
}
finally {
  if($postgresStopped){docker compose start postgres | Out-Null}
  if($redisStopped){docker compose start redis | Out-Null}
}
