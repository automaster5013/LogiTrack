$ErrorActionPreference = "Stop"
$metrics=Invoke-WebRequest http://localhost:8080/actuator/prometheus -UseBasicParsing
foreach($name in @("logitrack_outbox_backlog","logitrack_outbox_oldest_age_seconds","logitrack_dlq_backlog","logitrack_outbox_retries_total","logitrack_dlq_replays_total","logitrack_route_analysis_total","logitrack_report_pdf_total","http_server_requests_seconds_bucket","kafka_consumer_fetch_manager_records_lag")){
  if($metrics.Content-notmatch $name){throw "Missing recovery metric: $name"}
}
$rules=Invoke-RestMethod http://localhost:9090/api/v1/rules
$names=@($rules.data.groups.rules.name)
foreach($name in @("LogiTrackApiDown","LogiTrackRecoveryMetricRefreshFailing","LogiTrackOutboxFailed","LogiTrackOutboxBacklogGrowing","LogiTrackOutboxOldestPending","LogiTrackDeadLetterBacklog","LogiTrackRouteAnalysisDegraded","LogiTrackPdfRenderingFailing","LogiTrackApiServerErrors","LogiTrackApiLatencyHigh","LogiTrackTelemetryConsumerLagHigh","LogiTrackTelemetryConsumerMissing")){
  if($names-notcontains $name){throw "Missing Prometheus rule: $name"}
}
Write-Host "PASS: operational metrics exposed and 12 Prometheus alert rules loaded"
