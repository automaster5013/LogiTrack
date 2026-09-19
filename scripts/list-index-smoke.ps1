$ErrorActionPreference = "Stop"
$checks=@(
  @{table="deliveries";column="created_at";index="idx_deliveries_created_desc"},
  @{table="orders";column="created_at";index="idx_orders_created_desc"},
  @{table="route_snapshots";column="generated_at";index="idx_route_snapshots_generated_desc"},
  @{table="delivery_alerts";column="last_observed_at";index="idx_delivery_alert_observed_desc"},
  @{table="warehouse_tasks";column="created_at";index="idx_warehouse_tasks_created_desc"}
)
foreach($check in $checks){
  $exists=(docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT count(*) FROM pg_indexes WHERE schemaname='public' AND indexname='$($check.index)'").Trim()
  if($exists-ne"1"){throw "Missing index $($check.index)"}
  $plan=docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SET enable_seqscan=off; EXPLAIN SELECT * FROM $($check.table) ORDER BY $($check.column) DESC LIMIT 200"
  if(($plan-join"`n")-notmatch $check.index){throw "Query plan did not use $($check.index)"}
}
Write-Host "PASS: all bounded latest-first operational queries use matching indexes"
