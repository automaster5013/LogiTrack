from pathlib import Path

import yaml


config = yaml.safe_load(Path("infra/alertmanager.yml").read_text(encoding="utf-8"))
route = config.get("route", {})
if route.get("receiver") != "default-operations":
    raise AssertionError("Alertmanager default receiver drifted")
if set(route.get("group_by", [])) != {"alertname", "component", "severity"}:
    raise AssertionError("Alertmanager must group by alert identity, component, and severity")
if route.get("group_wait") != "30s" or route.get("group_interval") != "5m" or route.get("repeat_interval") != "4h":
    raise AssertionError("Alertmanager default grouping intervals drifted")

child_routes = route.get("routes", [])
expected_routes = {
    'severity="critical"': ("critical-operations", "30m"),
    'severity="warning"': ("warning-operations", "4h"),
}
actual_routes = {
    matcher: (child.get("receiver"), child.get("repeat_interval"))
    for child in child_routes
    for matcher in child.get("matchers", [])
}
if actual_routes != expected_routes:
    raise AssertionError("severity routing or repeat intervals drifted")

receiver_names = {receiver.get("name") for receiver in config.get("receivers", [])}
if receiver_names != {"default-operations", "critical-operations", "warning-operations"}:
    raise AssertionError("Alertmanager receiver set drifted")

inhibitions = config.get("inhibit_rules", [])
if len(inhibitions) != 1:
    raise AssertionError("exactly one critical-over-warning inhibition rule is required")
inhibition = inhibitions[0]
if inhibition.get("source_matchers") != ['severity="critical"'] or inhibition.get("target_matchers") != ['severity="warning"']:
    raise AssertionError("critical alerts must inhibit warning alerts")
if inhibition.get("equal") != ["component"]:
    raise AssertionError("alert inhibition must be scoped to the same component")

prometheus = yaml.safe_load(Path("infra/prometheus.yml").read_text(encoding="utf-8"))
targets = prometheus.get("alerting", {}).get("alertmanagers", [{}])[0].get("static_configs", [{}])[0].get("targets", [])
if targets != ["alertmanager:9093"]:
    raise AssertionError("Prometheus is not wired to the internal Alertmanager endpoint")

print("PASS: Alertmanager groups, routes, repeats, and inhibits classified alerts with bounded policy")
