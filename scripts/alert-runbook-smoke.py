from pathlib import Path
from urllib.parse import urlparse

import yaml


rules_path = Path("infra/prometheus-alerts.yml")
runbooks_path = Path("docs/alert-runbooks.md")
repository_url = "https://github.com/automaster5013/LogiTrack/blob/main/docs/alert-runbooks.md"

configuration = yaml.safe_load(rules_path.read_text(encoding="utf-8"))
alerts = [
    rule
    for group in configuration.get("groups", [])
    for rule in group.get("rules", [])
    if "alert" in rule
]
if len(alerts) != 22 or len({rule["alert"] for rule in alerts}) != len(alerts):
    raise AssertionError("expected 22 uniquely named Prometheus alerts")

expected_components = {"alerting", "api", "demo", "outbox", "recovery", "reporting", "retention", "routing", "telemetry"}
actual_components = {rule.get("labels", {}).get("component") for rule in alerts}
if actual_components != expected_components:
    raise AssertionError(f"alert component taxonomy drifted: {sorted(actual_components)}")
for rule in alerts:
    if rule.get("labels", {}).get("severity") not in {"critical", "warning"}:
        raise AssertionError(f"{rule['alert']} has an unsupported severity")

runbooks = runbooks_path.read_text(encoding="utf-8")
for rule in alerts:
    name = rule["alert"]
    annotations = rule.get("annotations", {})
    for field in ("summary", "description", "runbook_url"):
        if not annotations.get(field):
            raise AssertionError(f"{name} is missing the {field} annotation")

    expected_anchor = name.lower()
    expected_url = f"{repository_url}#{expected_anchor}"
    actual_url = annotations["runbook_url"]
    parsed = urlparse(actual_url)
    if actual_url != expected_url or parsed.scheme != "https":
        raise AssertionError(f"{name} runbook URL is not the stable main-branch HTTPS anchor")

    heading = f"## {name}"
    if runbooks.count(heading) != 1:
        raise AssertionError(f"{name} must have exactly one runbook section")
    section = runbooks.split(heading, 1)[1].split("\n## ", 1)[0]
    for required_step in ("- 영향:", "- 즉시 조치:", "- 진단:", "- 종료 기준:"):
        if required_step not in section:
            raise AssertionError(f"{name} runbook is missing {required_step}")

print("PASS: all 22 Prometheus alerts have routable components and complete, stable incident runbooks")
