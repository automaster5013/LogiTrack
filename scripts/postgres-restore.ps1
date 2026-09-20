param(
  [Parameter(Mandatory = $true)]
  [string]$BackupPath,
  [string]$TargetDatabase = "logitrack_restore",
  [switch]$Force
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

if (-not $Force) {
  throw "Restore replaces the target database. Re-run with -Force after confirming the target."
}
if ($TargetDatabase -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
  throw "TargetDatabase must be a valid unquoted PostgreSQL identifier"
}
if ($TargetDatabase -eq "logitrack") {
  throw "The primary logitrack database cannot be replaced by this online validation tool"
}

$resolvedBackup = (Resolve-Path -LiteralPath $BackupPath).Path
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$containerId = (& docker compose --project-directory $projectRoot ps -q postgres).Trim()
if ($LASTEXITCODE -ne 0 -or -not $containerId) {
  throw "PostgreSQL container is not running"
}

$containerTemp = "/tmp/logitrack-restore-$([guid]::NewGuid().ToString('N')).dump"
try {
  & docker cp $resolvedBackup "${containerId}:$containerTemp"
  if ($LASTEXITCODE -ne 0) { throw "Could not copy the backup into PostgreSQL" }

  $restoreCommand = 'PGPASSWORD="$POSTGRES_PASSWORD" pg_restore --list "' + $containerTemp + '" >/dev/null && PGPASSWORD="$POSTGRES_PASSWORD" dropdb --if-exists --force --username="$POSTGRES_USER" "' + $TargetDatabase + '" && PGPASSWORD="$POSTGRES_PASSWORD" createdb --username="$POSTGRES_USER" "' + $TargetDatabase + '" && PGPASSWORD="$POSTGRES_PASSWORD" pg_restore --exit-on-error --no-owner --no-acl --username="$POSTGRES_USER" --dbname="' + $TargetDatabase + '" "' + $containerTemp + '"'
  & docker compose --project-directory $projectRoot exec -T postgres sh -ec $restoreCommand
  if ($LASTEXITCODE -ne 0) { throw "PostgreSQL restore failed" }
} finally {
  & docker compose --project-directory $projectRoot exec -T postgres rm -f $containerTemp 2>$null
}

$TargetDatabase
