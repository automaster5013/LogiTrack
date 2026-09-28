import json
from pathlib import Path


dashboard_path = Path("infra/grafana/provisioning/dashboards/json/demo-cleanup-health.json")
provider_path = Path("infra/grafana/provisioning/dashboards/empty.yml")
datasource_path = Path("infra/grafana/provisioning/datasources/prometheus.yml")

dashboard = json.loads(dashboard_path.read_text(encoding="utf-8"))
if dashboard.get("uid") != "logitrack-demo-cleanup" or dashboard.get("title") != "LogiTrack Demo Cleanup Health":
    raise AssertionError("demo cleanup dashboard identity drifted")
if dashboard.get("refresh") != "30s" or dashboard.get("editable") is not False:
    raise AssertionError("demo cleanup dashboard refresh or immutability drifted")

panels = dashboard.get("panels", [])
if len(panels) != 8 or len({panel.get("id") for panel in panels}) != len(panels):
    raise AssertionError("demo cleanup dashboard must contain eight uniquely identified panels")

expressions = {
    target["expr"]
    for panel in panels
    for target in panel.get("targets", [])
    if "expr" in target
}
required_metrics = {
    "logitrack_demo_cleanup_deleted_total",
    "logitrack_demo_cleanup_failures_total",
    "logitrack_demo_cleanup_last_success_timestamp_seconds",
    "logitrack_demo_cleanup_monitor_started_timestamp_seconds",
    "LogiTrackDemoCleanupFailing",
    "logitrack_demo_active_deliveries",
    "logitrack_demo_target_deliveries",
    "logitrack_demo_replenishment_failures_total",
}
for metric in required_metrics:
    if not any(metric in expression for expression in expressions):
        raise AssertionError(f"dashboard does not query {metric}")
for panel in panels:
    if panel.get("datasource") != "Prometheus":
        raise AssertionError("dashboard panel does not use the provisioned Prometheus datasource name")

provider = provider_path.read_text(encoding="utf-8")
if "path: /etc/grafana/provisioning/dashboards/json" not in provider or "editable: false" not in provider:
    raise AssertionError("Grafana file provider does not load immutable LogiTrack dashboards")
if "name: Prometheus" not in datasource_path.read_text(encoding="utf-8"):
    raise AssertionError("Prometheus datasource name is not stable")

print("PASS: immutable demo cleanup dashboard covers health, throughput, failure, and alert state")
