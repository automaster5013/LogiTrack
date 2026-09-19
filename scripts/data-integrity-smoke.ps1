$ErrorActionPreference = "Stop"
$names = docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT conname FROM pg_constraint WHERE conname IN ('outbox_status_values','outbox_attempts_nonnegative','outbox_publication_state','warehouse_task_type_status','inventory_delta_shape','delivery_alert_resolution_state','dead_letter_replay_state','replay_plan_execution_state','deliveries_status_values','deliveries_completion_state','orders_origin_lat_range','orders_origin_lon_range','orders_destination_lat_range','orders_destination_lon_range','orders_required_text_nonblank','orders_timestamp_order') ORDER BY conname"
if (($names | Where-Object { $_.Trim() }).Count -ne 16) { throw "Expected 16 operational state constraints, got: $names" }
$immutableTriggers = docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT tgname FROM pg_trigger WHERE NOT tgisinternal AND tgname IN ('inventory_ledger_immutable','alert_policy_audits_immutable') ORDER BY tgname"
if (($immutableTriggers | Where-Object { $_.Trim() }).Count -ne 2) { throw "Expected immutable ledger/audit triggers, got: $immutableTriggers" }
$cascade = (docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT confdeltype FROM pg_constraint WHERE conname='outbox_retry_audits_outbox_event_id_fkey'").Trim()
if ($cascade -ne "c") { throw "Outbox retry audit FK must cascade with retained parent deletion" }
$replayCascade = (docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT confdeltype FROM pg_constraint WHERE conname='replay_audits_dead_letter_event_id_fkey'").Trim()
if ($replayCascade -ne "c") { throw "Replay audit FK must cascade with retained parent deletion" }

$invalidId = [guid]::NewGuid().ToString()
& docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U logitrack -d logitrack -c "INSERT INTO outbox_events(id,aggregate_type,aggregate_id,event_type,topic,event_key,payload,status,attempts,created_at,next_attempt_at) VALUES ('$invalidId','SMOKE','$invalidId','smoke.v1','smoke.v1','key','{}','PENDING',-1,now(),now())" 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { throw "Invalid negative outbox attempts unexpectedly passed DB constraints" }
$deliveryId = (docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT id FROM deliveries LIMIT 1").Trim()
if (!$deliveryId) { throw "A delivery is required for the integrity smoke test" }
& docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U logitrack -d logitrack -c "UPDATE deliveries SET status='DELIVERED',progress=0.5 WHERE id='$deliveryId'" 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { throw "Inconsistent delivery completion unexpectedly passed DB constraints" }
$orderId = (docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT id FROM orders LIMIT 1").Trim()
if (!$orderId) { throw "An order is required for the integrity smoke test" }
& docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U logitrack -d logitrack -c "UPDATE orders SET origin_lat=91 WHERE id='$orderId'" 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { throw "Out-of-range order coordinates unexpectedly passed DB constraints" }
& docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U logitrack -d logitrack -c "UPDATE orders SET order_number=' ' WHERE id='$orderId'" 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { throw "Blank order identity unexpectedly passed DB constraints" }
& docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U logitrack -d logitrack -c "UPDATE orders SET updated_at=created_at - interval '1 second' WHERE id='$orderId'" 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { throw "Reversed order timestamps unexpectedly passed DB constraints" }
$ledgerId = (docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT id FROM inventory_ledger LIMIT 1").Trim()
if (!$ledgerId) { throw "An inventory ledger entry is required for the integrity smoke test" }
& docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U logitrack -d logitrack -c "UPDATE inventory_ledger SET occurred_at=occurred_at WHERE id='$ledgerId'" 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { throw "Immutable inventory ledger unexpectedly allowed an update" }
$policyAuditId = (docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT id FROM alert_policy_audits LIMIT 1").Trim()
if (!$policyAuditId) { throw "An alert policy audit is required for the integrity smoke test" }
& docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U logitrack -d logitrack -c "DELETE FROM alert_policy_audits WHERE id='$policyAuditId'" 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { throw "Immutable alert policy audit unexpectedly allowed a delete" }
Write-Host "PASS: operational state constraints loaded, invalid states rejected, and immutable records protected"
