$ErrorActionPreference = "Stop"

$rows = Invoke-RestMethod "http://localhost:8080/api/reports/daily-kpis?days=14"
if ($rows.Count -ne 14) { throw "Expected 14 daily KPI rows, got $($rows.Count)" }
if ($rows[-1].totalDeliveries -lt 1) { throw "Expected today's delivery cohort to contain data" }
if ($rows[-1].onTimeRatePercent -lt 0 -or $rows[-1].onTimeRatePercent -gt 100) { throw "Invalid on-time rate" }

$csv = Invoke-WebRequest -UseBasicParsing "http://localhost:8080/api/reports/daily-kpis.csv?days=3"
if ($csv.StatusCode -ne 200) { throw "CSV endpoint returned $($csv.StatusCode)" }
if ($csv.Headers."Content-Disposition" -notmatch "logitrack-daily-kpis.csv") { throw "CSV attachment header is missing" }
if ($csv.Content -notmatch "date,total,active,delivered,delayed") { throw "CSV header is invalid" }

Write-Host "PASS: rows=$($rows.Count), today=$($rows[-1].totalDeliveries), onTime=$($rows[-1].onTimeRatePercent)%"

