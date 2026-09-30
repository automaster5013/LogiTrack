import json
import os
import subprocess
from pathlib import Path

import yaml


config = yaml.safe_load(Path("infra/alertmanager-paging.yml").read_text(encoding="utf-8"))
routes = config["route"]["routes"]
critical = next(route for route in routes if 'severity="critical"' in route["matchers"])
if critical["receiver"] != "critical-paging" or critical["repeat_interval"] != "30m":
    raise AssertionError("critical alerts must use the bounded paging receiver")

receivers = {receiver["name"]: receiver for receiver in config["receivers"]}
if set(receivers) != {"default-operations", "critical-paging", "warning-operations"}:
    raise AssertionError("paging receiver set drifted")
webhooks = receivers["critical-paging"].get("webhook_configs", [])
if len(webhooks) != 1:
    raise AssertionError("critical paging must have exactly one webhook destination")
webhook = webhooks[0]
if webhook.get("url_file") != "/run/secrets/alertmanager_critical_webhook_url":
    raise AssertionError("critical destination must come from the mounted secret file")
if webhook.get("send_resolved") is not True or webhook.get("max_alerts") != 100:
    raise AssertionError("paging must send resolution and bound notification size")
if webhook.get("http_config", {}).get("follow_redirects") is not False:
    raise AssertionError("paging webhook must not follow redirects")

override = Path("docker-compose.paging.yml").read_text(encoding="utf-8")
for contract in (
    "ALERTMANAGER_CRITICAL_WEBHOOK_URL_FILE:?",
    "/run/secrets/alertmanager_critical_webhook_url:ro",
    "/etc/alertmanager/alertmanager-paging.yml:ro",
):
    if contract not in override:
        raise AssertionError(f"paging Compose boundary is missing {contract}")

environment = os.environ.copy()
environment.update(
    POSTGRES_PASSWORD="paging_contract_postgres",
    GRAFANA_ADMIN_PASSWORD="paging_contract_grafana",
    ALERTMANAGER_CRITICAL_WEBHOOK_URL_FILE=str(Path("infra/alertmanager.yml").resolve()),
)
rendered = json.loads(subprocess.run(
    ["docker", "compose", "-f", "docker-compose.yml", "-f", "docker-compose.paging.yml", "config", "--format", "json"],
    check=True, capture_output=True, text=True, env=environment,
).stdout)
alertmanager = rendered["services"]["alertmanager"]
if alertmanager["command"][0] != "--config.file=/etc/alertmanager/alertmanager-paging.yml":
    raise AssertionError("paging override does not select the paging configuration")
secret_mount = next(
    mount for mount in alertmanager["volumes"]
    if mount["target"] == "/run/secrets/alertmanager_critical_webhook_url"
)
if secret_mount.get("read_only") is not True or secret_mount.get("type") != "bind":
    raise AssertionError("paging destination must be a read-only bind-mounted secret")

print("PASS: critical paging uses a mounted secret, sends recovery, and rejects redirects")
