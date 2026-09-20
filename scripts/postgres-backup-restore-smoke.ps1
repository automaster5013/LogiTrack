$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$smokeDirectory = Join-Path $projectRoot "output/backups/smoke"
$suffix = [guid]::NewGuid().ToString("N").Substring(0, 8)
$targetDatabase = "logitrack_restore_smoke_$suffix"
$sentinelTable = "backup_restore_smoke_$suffix"
$sentinelValue = "verified-$suffix"
$backupPath = $null

try {
  & docker compose --project-directory $projectRoot exec -T postgres sh -ec "PGPASSWORD=`"`$POSTGRES_PASSWORD`" psql --username=`"`$POSTGRES_USER`" --dbname=`"`$POSTGRES_DB`" --command=`"create table $sentinelTable (marker text not null); insert into $sentinelTable values ('$sentinelValue');`""
  if ($LASTEXITCODE -ne 0) { throw "Could not create the backup sentinel" }

  $backupPath = & (Join-Path $PSScriptRoot "postgres-backup.ps1") -OutputDirectory $smokeDirectory
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
  }
}
