$ErrorActionPreference = "Stop"
$names = docker compose exec -T postgres psql -U logitrack -d logitrack -tAc "SELECT conname FROM pg_constraint WHERE conname IN ('outbox_status_values','outbox_attempts_nonnegative','outbox_publication_state','warehouse_task_type_status','inventory_delta_shape','delivery_alert_resolution_state','dead_letter_replay_state','replay_plan_execution_state') ORDER BY conname"
if (($names | Where-Object { $_.Trim() }).Count -ne 8) { throw "Expected 8 operational state constraints, got: $names" }

$invalidId = [guid]::NewGuid().ToString()
& docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U logitrack -d logitrack -c "INSERT INTO outbox_events(id,aggregate_type,aggregate_id,event_type,topic,event_key,payload,status,attempts,created_at,next_attempt_at) VALUES ('$invalidId','SMOKE','$invalidId','smoke.v1','smoke.v1','key','{}','PENDING',-1,now(),now())" 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { throw "Invalid negative outbox attempts unexpectedly passed DB constraints" }
Write-Host "PASS: operational state constraints loaded and invalid outbox state rejected"
