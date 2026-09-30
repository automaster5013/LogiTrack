import json
import queue
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import yaml


IMAGE = "prom/alertmanager:v0.28.1@sha256:27c475db5fb156cab31d5c18a4251ac7ed567746a2483ff264516437a39b15ba"
container = f"logitrack-alertmanager-paging-smoke-{uuid.uuid4().hex[:12]}"
notifications: queue.Queue[dict] = queue.Queue()


class Receiver(BaseHTTPRequestHandler):
    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        notifications.put(json.loads(self.rfile.read(length)))
        self.send_response(200)
        self.end_headers()

    def log_message(self, _format: str, *_args: object) -> None:
        return


def docker(*arguments: str, capture: bool = False) -> str:
    result = subprocess.run(["docker", *arguments], check=True, capture_output=capture, text=True)
    return result.stdout.strip() if capture else ""


def api(base_url: str, alerts: list[dict]) -> None:
    request = urllib.request.Request(
        f"{base_url}/api/v2/alerts",
        data=json.dumps(alerts).encode(),
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=5):
        pass


def wait_ready(base_url: str) -> None:
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(f"{base_url}/-/ready", timeout=2) as response:
                if response.status == 200:
                    return
        except (urllib.error.URLError, ConnectionError, TimeoutError):
            pass
        time.sleep(1)
    raise AssertionError("paging Alertmanager did not become ready")


def next_status(expected: str) -> dict:
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        try:
            payload = notifications.get(timeout=1)
            if payload.get("status") == expected:
                return payload
        except queue.Empty:
            pass
    raise AssertionError(f"paging receiver did not receive {expected} notification")


# Bind all host interfaces so Linux containers can reach the fixture through
# the explicit host-gateway mapping. The randomly selected port exists only
# for this short-lived contract test.
server = ThreadingHTTPServer(("0.0.0.0", 0), Receiver)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()

try:
    with tempfile.TemporaryDirectory(prefix="logitrack-alertmanager-paging-") as temporary:
        root = Path(temporary)
        config = yaml.safe_load(Path("infra/alertmanager-paging.yml").read_text(encoding="utf-8"))
        config["route"]["group_wait"] = "1s"
        config["route"]["group_interval"] = "1s"
        config_path = root / "alertmanager.yml"
        config_path.write_text(yaml.safe_dump(config, sort_keys=False), encoding="utf-8")
        secret_path = root / "webhook-url"
        secret_path.write_text(f"http://host.docker.internal:{server.server_port}/critical\n", encoding="utf-8")

        docker(
            "run", "--detach", "--name", container,
            "--add-host", "host.docker.internal:host-gateway",
            "--publish", "127.0.0.1::9093",
            "--read-only", "--cap-drop", "ALL",
            "--security-opt", "no-new-privileges:true",
            "--memory", "256m", "--pids-limit", "128",
            "--volume", f"{config_path.resolve()}:/etc/alertmanager/alertmanager.yml:ro",
            "--volume", f"{secret_path.resolve()}:/run/secrets/alertmanager_critical_webhook_url:ro",
            IMAGE, "--config.file=/etc/alertmanager/alertmanager.yml",
        )
        published = docker("port", container, "9093/tcp", capture=True).splitlines()[0]
        base_url = f"http://127.0.0.1:{published.rsplit(':', 1)[1]}"
        wait_ready(base_url)

        now = datetime.now(timezone.utc)
        alert = {
            "labels": {"alertname": "PagingContractCritical", "component": "paging-smoke", "severity": "critical"},
            "annotations": {"summary": "paging contract critical"},
            "startsAt": now.isoformat(),
            "endsAt": (now + timedelta(minutes=5)).isoformat(),
        }
        api(base_url, [alert])
        firing = next_status("firing")
        if firing.get("receiver") != "critical-paging" or len(firing.get("alerts", [])) != 1:
            raise AssertionError("critical paging payload has the wrong receiver or alert count")

        alert["endsAt"] = (datetime.now(timezone.utc) - timedelta(seconds=5)).isoformat()
        api(base_url, [alert])
        resolved = next_status("resolved")
        if resolved.get("receiver") != "critical-paging":
            raise AssertionError("resolved paging payload used the wrong receiver")

        print("PASS: critical Alertmanager paging sends firing and resolved webhook notifications")
finally:
    server.shutdown()
    server.server_close()
    subprocess.run(["docker", "rm", "--force", container], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
