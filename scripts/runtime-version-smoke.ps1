$ErrorActionPreference = "Stop"

function Get-RuntimeVersion {
  $deadline = (Get-Date).AddSeconds(60)
  do {
    try {
      $response = Invoke-RestMethod http://localhost:3000/api/runtime-version -TimeoutSec 3
      if ($response.version) { return $response.version }
    } catch {}
    Start-Sleep -Seconds 2
  } while ((Get-Date) -lt $deadline)
  throw "Web runtime version endpoint did not become ready"
}

$metadata = Invoke-RestMethod http://localhost:3000/api/runtime-version -TimeoutSec 3
if (-not $metadata.revision) { throw "Runtime revision is missing" }
if (-not $metadata.builtAt) { throw "Runtime build timestamp is missing" }

$before = Get-RuntimeVersion
$stable = Get-RuntimeVersion
if ($before -ne $stable) { throw "Runtime version changed without a deployment" }

docker compose restart web | Out-Null
$deadline = (Get-Date).AddSeconds(60)
do {
  Start-Sleep -Seconds 2
  try { $after = (Invoke-RestMethod http://localhost:3000/api/runtime-version -TimeoutSec 3).version } catch { $after = $null }
} while ((!$after -or $after -eq $before) -and (Get-Date) -lt $deadline)

if (!$after -or $after -eq $before) { throw "Runtime version did not change after web restart" }
Write-Host "PASS: runtime version changed $before -> $after (revision $($metadata.revision), built $($metadata.builtAt))"
