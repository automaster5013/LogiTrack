param(
  [string]$OutputPath = (Join-Path $PSScriptRoot "..\.env")
)

$ErrorActionPreference = "Stop"
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $resolvedOutput) {
  throw "$resolvedOutput already exists; use rotate-local-secrets.ps1 to rotate persisted credentials safely"
}

function New-Secret {
  $bytes = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
  return [Convert]::ToBase64String($bytes).TrimEnd("=").Replace("+", "-").Replace("/", "_")
}

$templatePath = Join-Path $PSScriptRoot "..\.env.example"
$values = [ordered]@{}
foreach ($line in Get-Content -LiteralPath $templatePath) {
  if (-not $line -or $line.TrimStart().StartsWith("#")) { continue }
  $parts = $line.Split("=", 2)
  $values[$parts[0]] = if ($parts.Count -eq 2) { $parts[1] } else { "" }
}
$values["POSTGRES_PASSWORD"] = New-Secret
$values["GRAFANA_ADMIN_PASSWORD"] = New-Secret

$parent = Split-Path -Parent $resolvedOutput
if ($parent -and -not (Test-Path -LiteralPath $parent)) {
  New-Item -ItemType Directory -Path $parent | Out-Null
}
$content = $values.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
Set-Content -LiteralPath $resolvedOutput -Value $content -Encoding utf8NoBOM
Write-Host "Created $resolvedOutput with independent cryptographically random database and Grafana passwords."
