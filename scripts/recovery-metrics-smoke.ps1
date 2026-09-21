$ErrorActionPreference = "Stop"
$metrics=Invoke-WebRequest http://localhost:8080/actuator/prometheus -UseBasicParsing
foreach($name in @("logitrack_outbox_backlog","logitrack_outbox_oldest_age_seconds","logitrack_outbox_publish_failures_total","logitrack_dlq_backlog","logitrack_outbox_retries_total","logitrack_dlq_replays_total","logitrack_dlq_discards_total","logitrack_route_analysis_total","logitrack_report_pdf_total","logitrack_kpi_projection_last_success_timestamp_seconds","logitrack_kpi_projection_refresh_interval_seconds","logitrack_retention_deleted_total","logitrack_retention_failures_total","http_server_requests_seconds_bucket","kafka_consumer_coordinator_assigned_partitions")){
  if($metrics.Content-notmatch $name){throw "Missing recovery metric: $name"}
}
$rules=Invoke-RestMethod http://localhost:9090/api/v1/rules
$names=@($rules.data.groups.rules.name)
foreach($name in @("LogiTrackApiDown","LogiTrackRecoveryMetricRefreshFailing","LogiTrackOutboxFailed","LogiTrackOutboxPublisherFailing","LogiTrackOutboxBacklogGrowing","LogiTrackOutboxOldestPending","LogiTrackDeadLetterBacklog","LogiTrackRouteAnalysisDegraded","LogiTrackPdfRenderingFailing","LogiTrackKpiProjectionStale","LogiTrackApiServerErrors","LogiTrackApiLatencyHigh","LogiTrackTelemetryConsumerLagHigh","LogiTrackTelemetryConsumerMissing","LogiTrackRetentionCleanupFailing")){
  if($names-notcontains $name){throw "Missing Prometheus rule: $name"}
}
Write-Host "PASS: operational metrics exposed and 15 Prometheus alert rules loaded"
