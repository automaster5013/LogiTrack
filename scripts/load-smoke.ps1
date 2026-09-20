$ErrorActionPreference = "Stop"

Write-Host "Running idempotent delivery creation workload (20 RPS / 15 seconds)..."
docker compose stop simulator | Out-Null
try {
  python .\load\delivery_load.py --rate 20 --duration 15
  if ($LASTEXITCODE -ne 0) { throw "Load success criteria failed" }
} finally {
  docker compose up -d simulator | Out-Null
}
