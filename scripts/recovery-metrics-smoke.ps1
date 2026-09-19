$ErrorActionPreference = "Stop"
$metrics=Invoke-WebRequest http://localhost:8080/actuator/prometheus -UseBasicParsing
foreach($name in @("logitrack_outbox_backlog","logitrack_dlq_backlog")){
  if($metrics.Content-notmatch $name){throw "Missing recovery metric: $name"}
}
$rules=Invoke-RestMethod http://localhost:9090/api/v1/rules
$names=@($rules.data.groups.rules.name)
foreach($name in @("LogiTrackOutboxFailed","LogiTrackOutboxBacklogGrowing","LogiTrackDeadLetterBacklog")){
  if($names-notcontains $name){throw "Missing Prometheus rule: $name"}
}
Write-Host "PASS: recovery gauges exposed and 3 Prometheus alert rules loaded"
