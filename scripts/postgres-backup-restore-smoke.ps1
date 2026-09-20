$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$smokeDirectory = Join-Path $projectRoot "output/backups/smoke"
$suffix = [guid]::NewGuid().ToString("N").Substring(0, 8)
$targetDatabase = "logitrack_restore_smoke_$suffix"
$sentinelTable = "backup_restore_smoke_$suffix"
$sentinelValue = "verified-$suffix"
$backupPath = $null
$secondBackupPath = $null
$corruptPath = $null
$truncatedPath = $null

try {
  & docker compose --project-directory $projectRoot exec -T postgres sh -ec "PGPASSWORD=`"`$POSTGRES_PASSWORD`" psql --username=`"`$POSTGRES_USER`" --dbname=`"`$POSTGRES_DB`" --command=`"create table $sentinelTable (marker text not null); insert into $sentinelTable values ('$sentinelValue');`""
  if ($LASTEXITCODE -ne 0) { throw "Could not create the backup sentinel" }

  $backupPath = & (Join-Path $PSScriptRoot "postgres-backup.ps1") -OutputDirectory $smokeDirectory
  $checksumPath = "$backupPath.sha256"
  if (-not (Test-Path -LiteralPath $checksumPath)) { throw "Backup checksum sidecar was not created" }
  $secondBackupPath = & (Join-Path $PSScriptRoot "postgres-backup.ps1") -OutputDirectory $smokeDirectory
  if ($secondBackupPath -eq $backupPath -or -not (Test-Path -LiteralPath "$secondBackupPath.sha256")) {
    throw "Consecutive backups did not receive unique verified paths"
  }

  $corruptPath = "$backupPath.corrupt"
  Copy-Item -LiteralPath $backupPath -Destination $corruptPath
  $bytes = [System.IO.File]::ReadAllBytes($corruptPath)
  $bytes[[math]::Floor($bytes.Length / 2)] = $bytes[[math]::Floor($bytes.Length / 2)] -bxor 1
  [System.IO.File]::WriteAllBytes($corruptPath, $bytes)
  $expectedChecksum = ((Get-Content -LiteralPath $checksumPath -Raw).Trim() -split '\s+')[0]
  Set-Content -LiteralPath "$corruptPath.sha256" -Value "$expectedChecksum  $(Split-Path -Leaf $corruptPath)" -Encoding ascii
  try {
    & (Join-Path $PSScriptRoot "postgres-restore.ps1") -BackupPath $corruptPath -TargetDatabase "${targetDatabase}_corrupt" -Force
    throw "Corrupted backup was accepted"
  } catch {
    if ($_.Exception.Message -notmatch "checksum verification failed") { throw }
  }

  & docker compose --project-directory $projectRoot exec -T postgres sh -ec "PGPASSWORD=`"`$POSTGRES_PASSWORD`" createdb --username=`"`$POSTGRES_USER`" `"$targetDatabase`" && PGPASSWORD=`"`$POSTGRES_PASSWORD`" psql --username=`"`$POSTGRES_USER`" --dbname=`"$targetDatabase`" --command=`"create table restore_guard (marker text not null); insert into restore_guard values ('preserved');`""
  if ($LASTEXITCODE -ne 0) { throw "Could not create the restore safety sentinel" }
  $truncatedPath = "$backupPath.truncated"
  Copy-Item -LiteralPath $backupPath -Destination $truncatedPath
  $stream = [System.IO.File]::Open($truncatedPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write)
  try { $stream.SetLength([math]::Floor($stream.Length * 0.75)) } finally { $stream.Dispose() }
  $truncatedChecksum = (Get-FileHash -LiteralPath $truncatedPath -Algorithm SHA256).Hash.ToLowerInvariant()
  Set-Content -LiteralPath "$truncatedPath.sha256" -Value "$truncatedChecksum  $(Split-Path -Leaf $truncatedPath)" -Encoding ascii
  try {
    & (Join-Path $PSScriptRoot "postgres-restore.ps1") -BackupPath $truncatedPath -TargetDatabase $targetDatabase -Force
    throw "Truncated backup was accepted"
  } catch {
    if ($_.Exception.Message -eq "Truncated backup was accepted") { throw }
  }
  $guardValue = (& docker compose --project-directory $projectRoot exec -T postgres sh -ec "PGPASSWORD=`"`$POSTGRES_PASSWORD`" psql --tuples-only --no-align --username=`"`$POSTGRES_USER`" --dbname=`"$targetDatabase`" --command=`"select marker from restore_guard`"").Trim()
  if ($LASTEXITCODE -ne 0 -or $guardValue -ne "preserved") {
    throw "Failed staging restore damaged the existing target database"
  }
  $stagingCount = (& docker compose --project-directory $projectRoot exec -T postgres sh -ec "PGPASSWORD=`"`$POSTGRES_PASSWORD`" psql --tuples-only --no-align --username=`"`$POSTGRES_USER`" --dbname=postgres --command=`"select count(*) from pg_database where datname like '${targetDatabase}_staging_%'`"").Trim()
  if ($LASTEXITCODE -ne 0 -or $stagingCount -ne "0") {
    throw "Failed restore left a staging database behind"
  }
  & docker compose --project-directory $projectRoot exec -T postgres sh -ec "PGPASSWORD=`"`$POSTGRES_PASSWORD`" psql --username=`"`$POSTGRES_USER`" --dbname=`"`$POSTGRES_DB`" --command=`"drop table $sentinelTable`""
  if ($LASTEXITCODE -ne 0) { throw "Could not remove the source backup sentinel" }

  $restoredDatabase = & (Join-Path $PSScriptRoot "postgres-restore.ps1") -BackupPath $backupPath -TargetDatabase $targetDatabase -Force
  if ($restoredDatabase -ne $targetDatabase) { throw "Restore did not return the expected database name" }

  $restoredValue = (& docker compose --project-directory $projectRoot exec -T postgres sh -ec "PGPASSWORD=`"`$POSTGRES_PASSWORD`" psql --tuples-only --no-align --username=`"`$POSTGRES_USER`" --dbname=`"$targetDatabase`" --command=`"select marker from $sentinelTable`"").Trim()
  if ($LASTEXITCODE -ne 0 -or $restoredValue -ne $sentinelValue) {
    throw "Restored database does not contain the expected sentinel value"
  }

  Write-Output "PASS: PostgreSQL backup restored the sentinel row into an isolated database"
} finally {
  & docker compose --project-directory $projectRoot exec -T postgres sh -ec "PGPASSWORD=`"`$POSTGRES_PASSWORD`" psql --username=`"`$POSTGRES_USER`" --dbname=`"`$POSTGRES_DB`" --command=`"drop table if exists $sentinelTable`"" 2>$null
  & docker compose --project-directory $projectRoot exec -T postgres sh -ec "PGPASSWORD=`"`$POSTGRES_PASSWORD`" dropdb --if-exists --force --username=`"`$POSTGRES_USER`" `"$targetDatabase`"" 2>$null
  if ($backupPath -and (Test-Path -LiteralPath $backupPath)) {
    Remove-Item -LiteralPath $backupPath -Force
    Remove-Item -LiteralPath "$backupPath.sha256" -Force -ErrorAction SilentlyContinue
  }
  if ($secondBackupPath -and (Test-Path -LiteralPath $secondBackupPath)) {
    Remove-Item -LiteralPath $secondBackupPath -Force
    Remove-Item -LiteralPath "$secondBackupPath.sha256" -Force -ErrorAction SilentlyContinue
  }
  if ($corruptPath -and (Test-Path -LiteralPath $corruptPath)) {
    Remove-Item -LiteralPath $corruptPath -Force
    Remove-Item -LiteralPath "$corruptPath.sha256" -Force -ErrorAction SilentlyContinue
  }
  if ($truncatedPath -and (Test-Path -LiteralPath $truncatedPath)) {
    Remove-Item -LiteralPath $truncatedPath -Force
    Remove-Item -LiteralPath "$truncatedPath.sha256" -Force -ErrorAction SilentlyContinue
  }
}
