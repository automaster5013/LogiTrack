$ErrorActionPreference = "Stop"
$page = 0
$ids = [System.Collections.Generic.HashSet[string]]::new()
do {
  $result = Invoke-RestMethod "http://localhost:8080/api/operations/dlq-page?status=PENDING&page=$page&size=20"
  foreach($event in $result.items) {
    if(-not $ids.Add([string]$event.id)) { throw "DLQ pagination returned duplicate event $($event.id)" }
  }
  $page++
} while($result.hasMore)
$databaseCount = [int](docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT count(*) FROM dead_letter_events WHERE status='PENDING'").Trim()
if($ids.Count -ne $databaseCount -or $ids.Count -ne [int]$result.totalElements) {
  throw "DLQ pagination count mismatch: loaded=$($ids.Count), total=$($result.totalElements), database=$databaseCount"
}
Write-Host "PASS: all $($ids.Count) PENDING DLQ events are reachable across $page page(s) without mutation"
