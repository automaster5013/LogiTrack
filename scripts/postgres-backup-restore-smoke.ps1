$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$smokeDirectory = Join-Path $projectRoot "output/backups/smoke"
$suffix = [guid]::NewGuid().ToString("N").Substring(0, 8)
$targetDatabase = "logitrack_restore_smoke_$suffix"
$sentinelTable = "backup_restore_smoke_$suffix"
$sentinelValue = "verified-$suffix"
$backupPath = $null
$corruptPath = $null

try {
  & docker compose --project-directory $projectRoot exec -T postgres sh -ec "PGPASSWORD=`"`$POSTGRES_PASSWORD`" psql --username=`"`$POSTGRES_USER`" --dbname=`"`$POSTGRES_DB`" --command=`"create table $sentinelTable (marker text not null); insert into $sentinelTable values ('$sentinelValue');`""
  if ($LASTEXITCODE -ne 0) { throw "Could not create the backup sentinel" }

  $backupPath = & (Join-Path $PSScriptRoot "postgres-backup.ps1") -OutputDirectory $smokeDirectory
  $checksumPath = "$backupPath.sha256"
  if (-not (Test-Path -LiteralPath $checksumPath)) { throw "Backup checksum sidecar was not created" }

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
  if ($corruptPath -and (Test-Path -LiteralPath $corruptPath)) {
    Remove-Item -LiteralPath $corruptPath -Force
    Remove-Item -LiteralPath "$corruptPath.sha256" -Force -ErrorAction SilentlyContinue
  }
}
