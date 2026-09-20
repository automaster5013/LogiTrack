$ErrorActionPreference = "Stop"
$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$envPath = Join-Path $root ".env"
if (-not (Test-Path -LiteralPath $envPath)) {
  throw "No .env exists; run ./scripts/init-env.ps1 for a new environment"
}

function Read-Environment([string]$Path) {
  $result = @{}
  foreach ($line in Get-Content -LiteralPath $Path) {
    if (-not $line -or $line.TrimStart().StartsWith("#")) { continue }
    $parts = $line.Split("=", 2)
    $result[$parts[0]] = if ($parts.Count -eq 2) { $parts[1] } else { "" }
  }
  return $result
}

$required = @("POSTGRES_USER", "POSTGRES_PASSWORD", "GRAFANA_ADMIN_PASSWORD")
$oldValues = Read-Environment $envPath
foreach ($name in $required) {
  if (-not $oldValues[$name]) { throw ".env is missing $name" }
}
foreach ($service in @("postgres", "grafana")) {
  $containerId = (docker compose ps -q $service).Trim()
  if (-not $containerId -or (docker inspect --format '{{.State.Status}}' $containerId) -ne "running") {
    throw "$service must be running before local credentials can be rotated"
  }
}

$workDirectory = Join-Path $root "work"
New-Item -ItemType Directory -Path $workDirectory -Force | Out-Null
$candidatePath = Join-Path $workDirectory "local-env-rotation.env"
Remove-Item -LiteralPath $candidatePath -Force -ErrorAction SilentlyContinue
& (Join-Path $PSScriptRoot "init-env.ps1") -OutputPath $candidatePath
$newValues = Read-Environment $candidatePath

function Set-DatabasePassword([string]$Password) {
  $escapedUser = $oldValues.POSTGRES_USER.Replace('"', '""')
  $escapedPassword = $Password.Replace("'", "''")
  $sql = "ALTER ROLE `"$escapedUser`" WITH PASSWORD '$escapedPassword';"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U $oldValues.POSTGRES_USER -d postgres -c $sql | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "PostgreSQL credential rotation failed" }
}

try {
  Set-DatabasePassword $newValues.POSTGRES_PASSWORD
  docker compose exec -T grafana grafana cli admin reset-admin-password $newValues.GRAFANA_ADMIN_PASSWORD | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Grafana credential rotation failed" }
  Move-Item -LiteralPath $candidatePath -Destination $envPath -Force
} catch {
  try { Set-DatabasePassword $oldValues.POSTGRES_PASSWORD } catch { Write-Warning "PostgreSQL rollback failed" }
  try { docker compose exec -T grafana grafana cli admin reset-admin-password $oldValues.GRAFANA_ADMIN_PASSWORD | Out-Null } catch { Write-Warning "Grafana rollback failed" }
  Remove-Item -LiteralPath $candidatePath -Force -ErrorAction SilentlyContinue
  throw
}

docker compose up -d --wait --force-recreate postgres api grafana
if ($LASTEXITCODE -ne 0) { throw "Credentials changed, but affected containers did not recover" }
Write-Host "Rotated local PostgreSQL and Grafana credentials and recreated affected services."
