$ErrorActionPreference = "Stop"

Write-Host "Running idempotent delivery creation workload (20 RPS / 15 seconds)..."
python .\load\delivery_load.py --rate 20 --duration 15
if ($LASTEXITCODE -ne 0) { throw "Load success criteria failed" }

