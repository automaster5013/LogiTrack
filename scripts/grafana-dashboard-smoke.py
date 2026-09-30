import json
from pathlib import Path


dashboard_path = Path("infra/grafana/provisioning/dashboards/json/demo-cleanup-health.json")
slo_dashboard_path = Path("infra/grafana/provisioning/dashboards/json/api-availability-slo.json")
triage_dashboard_path = Path("infra/grafana/provisioning/dashboards/json/alert-triage.json")
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

slo_dashboard = json.loads(slo_dashboard_path.read_text(encoding="utf-8"))
if slo_dashboard.get("uid") != "logitrack-api-availability-slo" or slo_dashboard.get("title") != "LogiTrack API Availability SLO":
    raise AssertionError("API availability SLO dashboard identity drifted")
if slo_dashboard.get("refresh") != "30s" or slo_dashboard.get("editable") is not False:
    raise AssertionError("API availability SLO dashboard refresh or immutability drifted")

slo_panels = slo_dashboard.get("panels", [])
if len(slo_panels) != 6 or len({panel.get("id") for panel in slo_panels}) != len(slo_panels):
    raise AssertionError("API availability SLO dashboard must contain six uniquely identified panels")
slo_expressions = {
    target["expr"]
    for panel in slo_panels
    for target in panel.get("targets", [])
    if "expr" in target
}
for required in (
    "logitrack_api:slo_request_error_ratio:rate5m",
    "logitrack_api:slo_request_error_ratio:rate30m",
    "logitrack_api:slo_request_error_ratio:rate1h",
    "logitrack_api:slo_request_error_ratio:rate6h",
    "LogiTrackApiErrorBudget(Fast|Slow)Burn",
    "[30d]",
):
    if not any(required in expression for expression in slo_expressions):
        raise AssertionError(f"SLO dashboard does not query {required}")
for panel in slo_panels:
    if panel.get("datasource") != "Prometheus":
        raise AssertionError("SLO dashboard panel does not use the provisioned Prometheus datasource name")

triage_dashboard = json.loads(triage_dashboard_path.read_text(encoding="utf-8"))
if triage_dashboard.get("uid") != "logitrack-alert-triage" or triage_dashboard.get("title") != "LogiTrack Alert Triage":
    raise AssertionError("alert triage dashboard identity drifted")
if triage_dashboard.get("refresh") != "30s" or triage_dashboard.get("editable") is not False:
    raise AssertionError("alert triage dashboard refresh or immutability drifted")
if not any(link.get("url", "").endswith("docs/alert-runbooks.md") for link in triage_dashboard.get("links", [])):
    raise AssertionError("alert triage dashboard does not link to the incident runbooks")

triage_panels = triage_dashboard.get("panels", [])
if len(triage_panels) != 10 or len({panel.get("id") for panel in triage_panels}) != len(triage_panels):
    raise AssertionError("alert triage dashboard must contain ten uniquely identified panels")
triage_expressions = {
    target["expr"]
    for panel in triage_panels
    for target in panel.get("targets", [])
    if "expr" in target
}
for required in ('severity="critical"', 'severity="warning"', "component", 'alertstate="pending"', 'alertstate="firing"', "prometheus_rule_evaluation_failures_total", 'job="logitrack-alertmanager"', "prometheus_notifications_errors_total", "prometheus_notifications_dropped_total"):
    if not any(required in expression for expression in triage_expressions):
        raise AssertionError(f"alert triage dashboard does not query {required}")
for panel in triage_panels:
    if panel.get("datasource") != "Prometheus":
        raise AssertionError("alert triage dashboard panel does not use the provisioned Prometheus datasource name")

provider = provider_path.read_text(encoding="utf-8")
if "path: /etc/grafana/provisioning/dashboards/json" not in provider or "editable: false" not in provider:
    raise AssertionError("Grafana file provider does not load immutable LogiTrack dashboards")
if "name: Prometheus" not in datasource_path.read_text(encoding="utf-8"):
    raise AssertionError("Prometheus datasource name is not stable")

print("PASS: immutable Grafana dashboards cover demo cleanup, API availability SLO, and alert triage operations")
