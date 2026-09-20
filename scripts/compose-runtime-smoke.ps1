$ErrorActionPreference = "Stop"

$expectedServices = @(
  "postgres", "redis", "kafka", "analytics", "api", "simulator",
  "web", "tempo", "otel-collector", "prometheus", "grafana"
)
$statelessServices = @("analytics", "api", "simulator", "web", "otel-collector")
$expectedNetworks = @{
  postgres = @("logitrack_data")
  redis = @("logitrack_data")
  kafka = @("logitrack_data")
  analytics = @("logitrack_analytics-egress", "logitrack_observability")
  api = @("logitrack_analytics-egress", "logitrack_data", "logitrack_edge", "logitrack_observability")
  "api-replica" = @("logitrack_analytics-egress", "logitrack_data", "logitrack_edge", "logitrack_observability")
  simulator = @("logitrack_data")
  web = @("logitrack_edge")
  tempo = @("logitrack_observability")
  "otel-collector" = @("logitrack_observability")
  prometheus = @("logitrack_observability")
  grafana = @("logitrack_observability")
}

$running = @(docker compose ps --format json | ConvertFrom-Json)
if ($running.Service -contains "api-replica") {
  $expectedServices += "api-replica"
  $statelessServices += "api-replica"
}
foreach ($service in $expectedServices) {
  $state = $running | Where-Object Service -eq $service | Select-Object -First 1
  if (-not $state -or $state.State -ne "running" -or $state.Health -ne "healthy") {
    throw "$service is not running and healthy"
  }

  $containerId = (docker compose ps -q $service).Trim()
  $container = docker inspect $containerId | ConvertFrom-Json | Select-Object -First 1
  if ($container.HostConfig.RestartPolicy.Name -ne "unless-stopped") {
    throw "$service restart policy is not applied"
  }
  if ($container.Config.StopTimeout -ne 35) {
    throw "$service graceful shutdown timeout is not applied"
  }
  if ($container.HostConfig.LogConfig.Type -ne "json-file" -or
      $container.HostConfig.LogConfig.Config."max-size" -ne "10m" -or
      $container.HostConfig.LogConfig.Config."max-file" -ne "3") {
    throw "$service log rotation is not applied"
  }
  if ($container.HostConfig.Memory -le 0 -or $container.HostConfig.NanoCpus -le 0) {
    throw "$service resource limits are not applied"
  }
  if ($container.HostConfig.PidsLimit -le 0) {
    throw "$service process limit is not applied"
  }
  if ($container.HostConfig.SecurityOpt -notcontains "no-new-privileges:true") {
    throw "$service no-new-privileges boundary is not applied"
  }
  $actualNetworks = @($container.NetworkSettings.Networks.PSObject.Properties.Name | Sort-Object)
  $requiredNetworks = @($expectedNetworks[$service] | Sort-Object)
  if (($actualNetworks -join ",") -ne ($requiredNetworks -join ",")) {
    throw "$service runtime networks differ from the least-privilege topology"
  }
  foreach ($binding in $container.HostConfig.PortBindings.PSObject.Properties.Value) {
    foreach ($published in $binding) {
      if ($published.HostIp -ne "127.0.0.1") {
        throw "$service publishes a port outside loopback"
      }
    }
  }

  if ($service -in $statelessServices) {
    if (-not $container.HostConfig.ReadonlyRootfs) {
      throw "$service root filesystem is writable"
    }
    if ($container.HostConfig.CapDrop -notcontains "ALL") {
      throw "$service retains Linux capabilities"
    }
    if (-not $container.HostConfig.Tmpfs."/tmp") {
      throw "$service bounded /tmp is not applied"
    }
  }
}

$kafkaId = (docker compose ps -q kafka).Trim()
$kafka = docker inspect $kafkaId | ConvertFrom-Json | Select-Object -First 1
$kafkaEnvironment = @($kafka.Config.Env)
if ($kafkaEnvironment -notcontains "KAFKA_HEAP_OPTS=-Xms256m -Xmx512m") {
  throw "Kafka heap is not bounded below its container memory limit"
}
$kafkaVolumes = @($kafka.Mounts | Where-Object Type -eq "volume")
if ($kafkaVolumes.Count -ne 1 -or
    $kafkaVolumes[0].Name -ne "logitrack_kafka-data" -or
    $kafkaVolumes[0].Destination -ne "/tmp/kafka-logs") {
  throw "Kafka runtime volume topology is not isolated"
}
foreach ($target in @("/etc/kafka/secrets", "/mnt/shared/config", "/var/lib/kafka/data")) {
  if (-not $kafka.HostConfig.Tmpfs.$target) {
    throw "Kafka tmpfs $target is not applied"
  }
}

$web = Invoke-WebRequest -UseBasicParsing http://127.0.0.1:3000
$api = Invoke-RestMethod http://127.0.0.1:8080/actuator/health/readiness
if ($web.StatusCode -ne 200 -or $web.Content -notmatch "LogiTrack" -or $api.status -ne "UP") {
  throw "LogiTrack web or API readiness verification failed"
}

$metrics = (Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8080/actuator/prometheus).Content
if ($metrics -notmatch '(?m)^tomcat_threads_config_max_threads\{[^}]*\} 128\.0$' -or
    $metrics -notmatch '(?m)^tomcat_connections_config_max_connections\{[^}]*\} 512\.0$') {
  throw "API Tomcat runtime capacity limits are not applied"
}

Write-Host "PASS: running LogiTrack stack is healthy and matches hardened Compose policy"
