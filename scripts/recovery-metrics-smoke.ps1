$ErrorActionPreference = "Stop"
$metrics=Invoke-WebRequest http://localhost:8080/actuator/prometheus -UseBasicParsing
foreach($name in @("logitrack_outbox_backlog","logitrack_dlq_backlog","logitrack_outbox_retries_total","logitrack_dlq_replays_total","logitrack_route_analysis_total")){
  if($metrics.Content-notmatch $name){throw "Missing recovery metric: $name"}
}
$rules=Invoke-RestMethod http://localhost:9090/api/v1/rules
$names=@($rules.data.groups.rules.name)
foreach($name in @("LogiTrackApiDown","LogiTrackRecoveryMetricRefreshFailing","LogiTrackOutboxFailed","LogiTrackOutboxBacklogGrowing","LogiTrackDeadLetterBacklog","LogiTrackRouteAnalysisDegraded")){
  if($names-notcontains $name){throw "Missing Prometheus rule: $name"}
}
Write-Host "PASS: recovery and route metrics exposed and 6 Prometheus alert rules loaded"
