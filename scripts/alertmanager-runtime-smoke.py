import json
import subprocess
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path


IMAGE = "prom/alertmanager:v0.28.1@sha256:27c475db5fb156cab31d5c18a4251ac7ed567746a2483ff264516437a39b15ba"
CONFIG = Path("infra/alertmanager.yml").resolve()
suffix = uuid.uuid4().hex[:12]
container = f"logitrack-alertmanager-smoke-{suffix}"
volume = f"logitrack-alertmanager-smoke-{suffix}"


def docker(*arguments: str, capture: bool = False) -> str:
    result = subprocess.run(
        ["docker", *arguments],
        check=True,
        capture_output=capture,
        text=True,
    )
    return result.stdout.strip() if capture else ""


def request(base_url: str, path: str, method: str = "GET", body: object | None = None) -> object:
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        f"{base_url}{path}",
        data=data,
        method=method,
        headers={"Content-Type": "application/json"} if data is not None else {},
    )
    with urllib.request.urlopen(req, timeout=5) as response:
        payload = response.read()
        return json.loads(payload) if payload else {}


def wait_ready(base_url: str) -> None:
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(f"{base_url}/-/ready", timeout=2) as response:
                if response.status == 200:
                    return
        except (urllib.error.URLError, TimeoutError):
            pass
        time.sleep(1)
    raise AssertionError("Alertmanager did not become ready")


def start_container() -> str:
    docker(
        "run", "--detach", "--name", container,
        "--publish", "127.0.0.1::9093",
        "--read-only", "--cap-drop", "ALL",
        "--security-opt", "no-new-privileges:true",
        "--memory", "256m", "--pids-limit", "128",
        "--volume", f"{CONFIG}:/etc/alertmanager/alertmanager.yml:ro",
        "--volume", f"{volume}:/alertmanager",
        IMAGE,
        "--config.file=/etc/alertmanager/alertmanager.yml",
        "--storage.path=/alertmanager",
    )
    published = docker("port", container, "9093/tcp", capture=True).splitlines()[0]
    base_url = f"http://127.0.0.1:{published.rsplit(':', 1)[1]}"
    wait_ready(base_url)
    return base_url


try:
    docker("volume", "create", volume)
    base_url = start_container()

    now = datetime.now(timezone.utc)
    ends_at = now + timedelta(minutes=10)
    alerts = [
        {
            "labels": {"alertname": "ContractCritical", "component": "contract-smoke", "severity": "critical"},
            "annotations": {"summary": "contract smoke critical"},
            "startsAt": now.isoformat(),
            "endsAt": ends_at.isoformat(),
        },
        {
            "labels": {"alertname": "ContractWarning", "component": "contract-smoke", "severity": "warning"},
            "annotations": {"summary": "contract smoke warning"},
            "startsAt": now.isoformat(),
            "endsAt": ends_at.isoformat(),
        },
    ]
    request(base_url, "/api/v2/alerts", "POST", alerts)
    time.sleep(2)
    active = request(base_url, "/api/v2/alerts")
    by_severity = {item["labels"]["severity"]: item for item in active if item["labels"].get("component") == "contract-smoke"}
    critical = by_severity.get("critical")
    warning = by_severity.get("warning")
    if not critical or critical["status"]["state"] != "active" or critical["receivers"] != [{"name": "critical-operations"}]:
        raise AssertionError("critical alert did not route to the critical receiver")
    if not warning or warning["status"]["state"] != "suppressed" or len(warning["status"]["inhibitedBy"]) != 1:
        raise AssertionError("warning alert was not inhibited by the same-component critical alert")
    if warning["receivers"] != [{"name": "warning-operations"}]:
        raise AssertionError("warning alert did not route to the warning receiver")

    silence = request(
        base_url,
        "/api/v2/silences",
        "POST",
        {
            "matchers": [{"name": "component", "value": "contract-smoke", "isRegex": False}],
            "startsAt": now.isoformat(),
            "endsAt": ends_at.isoformat(),
            "createdBy": "alertmanager-runtime-smoke",
            "comment": "verify restart-persistent silence lifecycle",
        },
    )
    silence_id = silence.get("silenceID")
    if not silence_id:
        raise AssertionError("Alertmanager did not create a silence")

    docker("stop", "--timeout", "10", container)
    docker("rm", container)
    base_url = start_container()
    persisted = request(base_url, f"/api/v2/silence/{silence_id}")
    if persisted.get("id") != silence_id or persisted.get("status", {}).get("state") != "active":
        raise AssertionError("silence did not survive an Alertmanager restart")
    request(base_url, f"/api/v2/silence/{silence_id}", "DELETE")
    deleted = request(base_url, f"/api/v2/silence/{silence_id}")
    if deleted.get("status", {}).get("state") != "expired":
        raise AssertionError("silence cleanup did not expire the test silence")

    print("PASS: Alertmanager routes severity, inhibits component noise, and persists and cleans silences across restart")
finally:
    subprocess.run(["docker", "rm", "--force", container], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["docker", "volume", "rm", "--force", volume], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
