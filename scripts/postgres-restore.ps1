param(
  [Parameter(Mandatory = $true)]
  [string]$BackupPath,
  [string]$TargetDatabase = "logitrack_restore",
  [switch]$Force,
  [switch]$AllowUnverified
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

if (-not $Force) {
  throw "Restore replaces the target database. Re-run with -Force after confirming the target."
}
if ($TargetDatabase -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
  throw "TargetDatabase must be a valid unquoted PostgreSQL identifier"
}
if ($TargetDatabase.Length -gt 40) {
  throw "TargetDatabase must be at most 40 characters so a staging database can be created safely"
}
if ($TargetDatabase -eq "logitrack") {
  throw "The primary logitrack database cannot be replaced by this online validation tool"
}

$resolvedBackup = (Resolve-Path -LiteralPath $BackupPath).Path
$checksumPath = "$resolvedBackup.sha256"
if (Test-Path -LiteralPath $checksumPath) {
  $checksumLine = (Get-Content -LiteralPath $checksumPath -Raw).Trim()
  if ($checksumLine -notmatch '^([0-9a-fA-F]{64})\s+\*?(.+)$') {
    throw "Backup checksum file is malformed"
  }
  if ($Matches[2] -ne (Split-Path -Leaf $resolvedBackup)) {
    throw "Backup checksum refers to a different file"
  }
  $actualChecksum = (Get-FileHash -LiteralPath $resolvedBackup -Algorithm SHA256).Hash
  if ($actualChecksum -ne $Matches[1]) {
    throw "Backup checksum verification failed"
  }
} elseif (-not $AllowUnverified) {
  throw "Backup checksum is missing; use -AllowUnverified only for a trusted legacy dump"
}
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$containerId = (& docker compose --project-directory $projectRoot ps -q postgres).Trim()
if ($LASTEXITCODE -ne 0 -or -not $containerId) {
  throw "PostgreSQL container is not running"
}

$containerTemp = "/tmp/logitrack-restore-$([guid]::NewGuid().ToString('N')).dump"
$stagingDatabase = "${TargetDatabase}_staging_$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$restoreSucceeded = $false
try {
  & docker cp $resolvedBackup "${containerId}:$containerTemp"
  if ($LASTEXITCODE -ne 0) { throw "Could not copy the backup into PostgreSQL" }

  $restoreCommand = 'PGPASSWORD="$POSTGRES_PASSWORD" pg_restore --list "' + $containerTemp + '" >/dev/null && PGPASSWORD="$POSTGRES_PASSWORD" createdb --username="$POSTGRES_USER" "' + $stagingDatabase + '" >/dev/null && PGPASSWORD="$POSTGRES_PASSWORD" pg_restore --exit-on-error --no-owner --no-acl --username="$POSTGRES_USER" --dbname="' + $stagingDatabase + '" "' + $containerTemp + '" && PGPASSWORD="$POSTGRES_PASSWORD" dropdb --if-exists --force --username="$POSTGRES_USER" "' + $TargetDatabase + '" >/dev/null 2>&1 && PGPASSWORD="$POSTGRES_PASSWORD" psql --username="$POSTGRES_USER" --dbname=postgres --set=ON_ERROR_STOP=1 --command=''alter database "' + $stagingDatabase + '" rename to "' + $TargetDatabase + '"'' >/dev/null'
  & docker compose --project-directory $projectRoot exec -T postgres sh -ec $restoreCommand
  if ($LASTEXITCODE -ne 0) { throw "PostgreSQL restore failed" }
  $restoreSucceeded = $true
} finally {
  if (-not $restoreSucceeded) {
    $cleanupCommand = 'PGPASSWORD="$POSTGRES_PASSWORD" dropdb --if-exists --force --username="$POSTGRES_USER" "' + $stagingDatabase + '"'
    & docker compose --project-directory $projectRoot exec -T postgres sh -ec $cleanupCommand 2>$null
  }
  & docker compose --project-directory $projectRoot exec -T postgres rm -f $containerTemp 2>$null
}

$TargetDatabase
