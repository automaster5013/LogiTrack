$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$smokeDirectory = Join-Path $projectRoot "output/backups/smoke"
$targetDatabase = "logitrack_restore_smoke_$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$backupPath = $null

try {
  $backupPath = & (Join-Path $PSScriptRoot "postgres-backup.ps1") -OutputDirectory $smokeDirectory
  $restoredDatabase = & (Join-Path $PSScriptRoot "postgres-restore.ps1") -BackupPath $backupPath -TargetDatabase $targetDatabase -Force
  if ($restoredDatabase -ne $targetDatabase) { throw "Restore did not return the expected database name" }

  $tableCount = & docker compose --project-directory $projectRoot exec -T postgres sh -ec "PGPASSWORD=`"`$POSTGRES_PASSWORD`" psql --tuples-only --no-align --username=`"`$POSTGRES_USER`" --dbname=`"$targetDatabase`" --command=`"select count(*) from information_schema.tables where table_schema = 'public'`""
  if ($LASTEXITCODE -ne 0 -or [int]$tableCount -lt 10) {
    throw "Restored database does not contain the expected application schema"
  }

  Write-Output "PASS: PostgreSQL backup restored into isolated database with $tableCount public tables"
} finally {
  & docker compose --project-directory $projectRoot exec -T postgres sh -ec "PGPASSWORD=`"`$POSTGRES_PASSWORD`" dropdb --if-exists --force --username=`"`$POSTGRES_USER`" `"$targetDatabase`"" 2>$null
  if ($backupPath -and (Test-Path -LiteralPath $backupPath)) {
    Remove-Item -LiteralPath $backupPath -Force
  }
}
