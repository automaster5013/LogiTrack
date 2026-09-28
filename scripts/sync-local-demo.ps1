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
  $env:LOGITRACK_DEMO_STALE_AFTER_SECONDS = "120"
  $env:LOGITRACK_DEMO_SEED_INITIAL_DELAY_MS = "2000"
  $env:LOGITRACK_DEMO_SEED_DELAY_MS = "5000"

  docker compose up -d --build api simulator web
  if ($LASTEXITCODE -ne 0) { throw "Local live demo rebuild failed" }

  $deadline = (Get-Date).AddSeconds(120)
  do {
    try {
      $runtime = Invoke-RestMethod http://localhost:3000/api/runtime-version -TimeoutSec 3
      $page = Invoke-RestMethod 'http://localhost:8080/api/deliveries/page?page=0&size=100' -TimeoutSec 5
      $freshDemo = @($page.items | Where-Object {
        $_.vehicleId -like 'TRUCK-DEMO-*' -and $_.status -ne 'DELIVERED' -and $_.lastTelemetryAt -and
        ([DateTime]::UtcNow - ([DateTime]$_.lastTelemetryAt).ToUniversalTime()).TotalSeconds -lt 90
      })
    } catch {
      $runtime = $null
      $freshDemo = @()
    }
    if ($runtime -and $runtime.revision -eq $revision -and $runtime.environment -eq "local" -and $freshDemo.Count -gt 0) {
      Write-Host "PASS: local revision $revision has $($freshDemo.Count) actively moving demo vehicles"
      exit 0
    }
    Start-Sleep -Seconds 3
  } while ((Get-Date) -lt $deadline)
  throw "Local live demo did not produce fresh moving vehicle telemetry"
} finally {
  Pop-Location
}
