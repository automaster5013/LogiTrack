$ErrorActionPreference = "Stop"
$compose = @("compose", "-p", "logitrack-perf", "-f", "docker-compose.perf.yml")
$rate = 10
$duration = 15
$warmup = 20
$expectedRows = $rate * $duration + $warmup

try {
  & docker @compose up -d --build
  if ($LASTEXITCODE -ne 0) { throw "Could not start the isolated performance stack" }

  $deadline = (Get-Date).AddMinutes(2)
  do {
    Start-Sleep -Seconds 2
    try { $ready = (Invoke-RestMethod http://localhost:18080/actuator/health/readiness).status -eq "UP" } catch { $ready = $false }
  } while (-not $ready -and (Get-Date) -lt $deadline)
  if (-not $ready) { throw "Isolated performance API did not become ready" }

  python .\load\delivery_load.py --base-url http://localhost:18080 --rate $rate --duration $duration --workers 24 --warmup $warmup --unique
  if ($LASTEXITCODE -ne 0) { throw "Unique delivery workload failed its success criteria" }
  $count = & docker @compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT COUNT(*) FROM deliveries WHERE order_number LIKE 'LOAD-%';"
  if ([int]$count.Trim() -ne $expectedRows) { throw "Expected $expectedRows isolated deliveries, got $($count.Trim())" }
  Write-Host "PASS: isolated rows=$($count.Trim()); primary project data was untouched"
} finally {
  & docker @compose down -v --remove-orphans
}
