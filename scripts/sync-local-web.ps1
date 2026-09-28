$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot
Push-Location $workspace
try {
  $revision = (git rev-parse HEAD).Trim()
  if ($revision -notmatch "^[0-9a-f]{40}$") { throw "Current Git revision is invalid" }
  $env:APP_REVISION = $revision
  $env:APP_BUILD_TIME = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
  docker compose up -d --build --no-deps web
  if ($LASTEXITCODE -ne 0) { throw "Local web rebuild failed" }

  $deadline = (Get-Date).AddSeconds(90)
  do {
    try { $runtime = Invoke-RestMethod http://localhost:3000/api/runtime-version -TimeoutSec 3 } catch { $runtime = $null }
    if ($runtime -and $runtime.revision -eq $revision) {
      Write-Host "PASS: local web is running revision $revision (built $($runtime.builtAt))"
      exit 0
    }
    Start-Sleep -Seconds 2
  } while ((Get-Date) -lt $deadline)
  throw "Local web did not report the expected revision $revision"
} finally {
  Pop-Location
}
