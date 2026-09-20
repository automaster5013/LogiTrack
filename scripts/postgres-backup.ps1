param(
  [string]$OutputDirectory = (Join-Path $PSScriptRoot "../output/backups")
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outputPath = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $outputPath | Out-Null

$containerId = (& docker compose --project-directory $projectRoot ps -q postgres).Trim()
if ($LASTEXITCODE -ne 0 -or -not $containerId) {
  throw "PostgreSQL container is not running"
}

$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssfffZ") + "-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
$containerTemp = "/tmp/logitrack-$stamp.dump"
$backupPath = Join-Path $outputPath "logitrack-$stamp.dump"
$dumpCommand = 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump --format=custom --no-owner --no-acl --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --file="' + $containerTemp + '" && pg_restore --list "' + $containerTemp + '" >/dev/null'

try {
  & docker compose --project-directory $projectRoot exec -T postgres sh -ec $dumpCommand
  if ($LASTEXITCODE -ne 0) { throw "PostgreSQL backup failed" }

  & docker cp "${containerId}:$containerTemp" $backupPath
  if ($LASTEXITCODE -ne 0) { throw "Could not copy PostgreSQL backup to the host" }
} finally {
  & docker compose --project-directory $projectRoot exec -T postgres rm -f $containerTemp 2>$null
}

$file = Get-Item -LiteralPath $backupPath
if ($file.Length -le 0) { throw "PostgreSQL backup is empty" }
$checksum = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
$checksumPath = "$($file.FullName).sha256"
Set-Content -LiteralPath $checksumPath -Value "$checksum  $($file.Name)" -Encoding ascii
$file.FullName
