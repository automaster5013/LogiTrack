$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot
Push-Location $workspace
try {
  $revision = (git rev-parse HEAD).Trim()
  if ($revision -notmatch "^[0-9a-f]{40}$") { throw "Current Git revision is invalid" }

  $env:APP_REVISION = $revision
  $env:APP_BUILD_TIME = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
  $env:APP_ENVIRONMENT = "local"
  $env:LOGITRACK_DEMO_SEED_ENABLED = "true"
  $env:LOGITRACK_DEMO_TARGET_ACTIVE_DELIVERIES = "15"
  $env:LOGITRACK_DEMO_STALE_AFTER_SECONDS = "300"
  $env:LOGITRACK_DEMO_COMPLETED_RETENTION = "30m"
  $env:LOGITRACK_DEMO_CLEANUP_BATCH_SIZE = "250"
  $env:LOGITRACK_DEMO_SEED_INITIAL_DELAY_MS = "2000"
  $env:LOGITRACK_DEMO_SEED_DELAY_MS = "5000"
  $env:SIMULATION_INTERVAL_SECONDS = "1"
  $env:SIMULATION_STEPS = "120"
  # Reserve five workers for ad-hoc deliveries while the 15-vehicle demo
  # fleet is active. Without headroom, routine smoke requests can starve.
  $env:SIMULATION_MAX_WORKERS = "20"

  docker compose up -d --build api simulator web
  if ($LASTEXITCODE -ne 0) { throw "Local live demo rebuild failed" }

  # kafka-init is a one-shot dependency. Remove its successful, stopped
  # container so routine local synchronization does not leave disposable
  # Docker objects behind.
  docker compose rm -f kafka-init
  if ($LASTEXITCODE -ne 0) { throw "Local Kafka initialization container cleanup failed" }

  $deadline = (Get-Date).AddSeconds(120)
  do {
    try {
      $runtime = Invoke-RestMethod http://localhost:3000/api/runtime-version -TimeoutSec 3
      $deliveries = Invoke-RestMethod 'http://localhost:8080/api/deliveries?limit=500' -TimeoutSec 5
      $freshDemo = @($deliveries | Where-Object {
        $_.vehicleId -like 'TRUCK-DEMO-*' -and $_.status -ne 'DELIVERED' -and $_.lastTelemetryAt -and
        ([DateTime]::UtcNow - ([DateTime]$_.lastTelemetryAt).ToUniversalTime()).TotalSeconds -lt 90
      })
    } catch {
      $runtime = $null
      $freshDemo = @()
    }
    if ($runtime -and $runtime.revision -eq $revision -and $runtime.environment -eq "local" -and $freshDemo.Count -eq 15) {
      Write-Host "PASS: local revision $revision has $($freshDemo.Count) actively moving demo vehicles"
      exit 0
    }
    Start-Sleep -Seconds 3
  } while ((Get-Date) -lt $deadline)
  throw "Local live demo did not sustain the expected 15 fresh moving vehicles"
} finally {
  Pop-Location
}
