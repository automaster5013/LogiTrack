$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $repoRoot "output\pdf"
$outputFile = Join-Path $outputDirectory "logitrack-daily-kpi-report.pdf"
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

$response = Invoke-WebRequest -UseBasicParsing "http://localhost:8080/api/reports/daily-kpis.pdf?days=30" -OutFile $outputFile -PassThru
if ($response.StatusCode -ne 200) { throw "PDF endpoint returned $($response.StatusCode)" }
if ($response.Headers."Content-Type" -notmatch "application/pdf") { throw "PDF content type is invalid" }
if ($response.Headers."Content-Disposition" -notmatch "logitrack-daily-kpi-report.pdf") { throw "PDF attachment header is missing" }

$signature = [System.IO.File]::ReadAllBytes($outputFile)[0..4]
if ([System.Text.Encoding]::ASCII.GetString($signature) -ne "%PDF-") { throw "PDF signature is invalid" }
if ((Get-Item $outputFile).Length -lt 5000) { throw "PDF output is unexpectedly small" }

Write-Host "PASS: PDF report saved to $outputFile ($((Get-Item $outputFile).Length) bytes)"
