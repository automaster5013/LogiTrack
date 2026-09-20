$ErrorActionPreference = "Stop"
$simulatorWasRunning = (docker compose ps --status running --services) -contains "simulator"
$pendingDlqBefore = (docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT count(*) FROM dead_letter_events WHERE status='PENDING'").Trim()

try {
  if ($simulatorWasRunning) { docker compose stop simulator | Out-Null }
  Get-Content -Raw .\load\telemetry_load.py | docker compose run --rm -T --no-deps simulator python -
  if ($LASTEXITCODE -ne 0) { throw "Telemetry reflection success criteria failed" }
  docker compose exec -T kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server kafka:29092 --describe --group control-api-telemetry-v1
} finally {
  if ($simulatorWasRunning) {
    docker compose up -d --wait simulator | Out-Null
    Start-Sleep -Seconds 5
    $pendingDlqAfter = (docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT count(*) FROM dead_letter_events WHERE status='PENDING'").Trim()
    if ([int]$pendingDlqAfter -ne [int]$pendingDlqBefore) {
      throw "Simulator resume polluted the DLQ: before=$pendingDlqBefore after=$pendingDlqAfter"
    }
  }
}
