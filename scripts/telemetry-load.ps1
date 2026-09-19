$ErrorActionPreference = "Stop"
$simulatorWasRunning = (docker compose ps --status running --services) -contains "simulator"

try {
  if ($simulatorWasRunning) { docker compose stop simulator | Out-Null }
  Get-Content -Raw .\load\telemetry_load.py | docker compose run --rm -T --no-deps simulator python -
  if ($LASTEXITCODE -ne 0) { throw "Telemetry reflection success criteria failed" }
  docker compose exec -T kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server kafka:29092 --describe --group control-api-telemetry-v1
} finally {
  if ($simulatorWasRunning) { docker compose up -d simulator | Out-Null }
}

