$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$prometheusConfig = Join-Path $workspace "infra"
$metrics=Invoke-WebRequest http://localhost:8080/actuator/prometheus -UseBasicParsing
foreach($name in @("logitrack_outbox_backlog","logitrack_outbox_oldest_age_seconds","logitrack_outbox_publish_failures_total","logitrack_dlq_backlog","logitrack_outbox_retries_total","logitrack_dlq_replays_total","logitrack_dlq_discards_total","logitrack_route_analysis_total","logitrack_report_pdf_total","logitrack_kpi_projection_last_success_timestamp_seconds","logitrack_kpi_projection_refresh_interval_seconds","logitrack_retention_deleted_total","logitrack_retention_failures_total","logitrack_demo_active_deliveries","logitrack_demo_target_deliveries","logitrack_demo_replenishment_failures_total","http_server_requests_seconds_bucket","kafka_consumer_coordinator_assigned_partitions")){
  if($metrics.Content-notmatch $name){throw "Missing recovery metric: $name"}
}
$rules=Invoke-RestMethod http://localhost:9090/api/v1/rules
$names=@($rules.data.groups.rules.name)
foreach($name in @("LogiTrackApiDown","LogiTrackRecoveryMetricRefreshFailing","LogiTrackOutboxFailed","LogiTrackOutboxPublisherFailing","LogiTrackOutboxBacklogGrowing","LogiTrackOutboxOldestPending","LogiTrackDeadLetterBacklog","LogiTrackRouteAnalysisDegraded","LogiTrackPdfRenderingFailing","LogiTrackKpiProjectionStale","LogiTrackApiServerErrors","LogiTrackApiLatencyHigh","LogiTrackTelemetryConsumerLagHigh","LogiTrackTelemetryConsumerMissing","LogiTrackRetentionCleanupFailing","LogiTrackDemoCleanupFailing","LogiTrackDemoFleetBelowTarget")){
  if($names-notcontains $name){throw "Missing Prometheus rule: $name"}
}
docker run --rm --entrypoint promtool --volume "${prometheusConfig}:/etc/prometheus:ro" prom/prometheus:v3.5.0@sha256:63805ebb8d2b3920190daf1cb14a60871b16fd38bed42b857a3182bc621f4996 test rules /etc/prometheus/prometheus-alerts.test.yml
if($LASTEXITCODE-ne 0){throw "Prometheus alert behavior tests failed"}
Write-Host "PASS: operational metrics exposed, 17 Prometheus alert rules loaded, and demo cleanup alert behavior verified"
