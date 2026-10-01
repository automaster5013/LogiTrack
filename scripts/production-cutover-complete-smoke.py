import hashlib
import json
import subprocess
import sys
import tempfile
from copy import deepcopy
from pathlib import Path


repo = Path(__file__).resolve().parents[1]
validator = repo / "scripts/production-cutover-complete.py"
revision = "a" * 40
account_id = "123456789012"
now = "2026-10-02T01:00:00Z"
roots = ["state", "alerting", "audit", "certificates", "data", "compute", "edge"]
regional_alarms = [
    "logitrack-production-audit-root-usage",
    "logitrack-production-audit-access-denied-spike",
    "logitrack-production-origin-certificate-expiry",
    *[f"logitrack-production-kafka-{broker}-under-min-isr" for broker in (1, 2, 3)],
    "logitrack-production-kafka-offline-partitions",
    *[f"logitrack-production-kafka-{broker}-disk-high" for broker in (1, 2, 3)],
    "logitrack-production-cache-engine-cpu-high",
    "logitrack-production-cache-evictions",
    "logitrack-production-database-cpu-high",
    "logitrack-production-database-storage-low",
    "logitrack-production-waf-blocked-requests",
    "logitrack-production-web-unhealthy",
    "logitrack-production-target-5xx-rate",
    "logitrack-production-load-balancer-5xx",
    "logitrack-production-target-p95-latency",
    "logitrack-production-api-running-tasks",
    "logitrack-production-web-running-tasks",
]
global_alarms = [
    "logitrack-production-viewer-certificate-expiry",
    "logitrack-production-cloudfront-5xx-rate",
    "logitrack-production-viewer-waf-blocks",
]


with tempfile.TemporaryDirectory() as directory:
    work = Path(directory)
    receipts = work / "receipts"
    receipts.mkdir()
    manifest = {
        "schema_version": 1,
        "revision": revision,
        "change_ticket_url": "https://changes.example.test/LOGI-44",
        "approvals": [{"role": role, "actor": f"{role}-owner", "approved_at": "2026-09-30T12:00:00Z"} for role in ("business", "security", "operations")],
        "window": {"start": "2026-10-02T00:00:00Z", "end": "2026-10-02T02:00:00Z"},
        "terraform_plans": {f"production-{root}": {"revision": revision, "sha256": format(index + 1, "x") * 64, "destructive_changes": False, "planned_at": "2026-10-01T12:00:00Z"} for index, root in enumerate(roots)},
        "readiness": {"regional_paging_subscription": "confirmed", "global_paging_subscription": "confirmed", "origin_certificate": "issued", "viewer_certificate": "issued", "dns_ttl_seconds": 60},
        "drills": {name: {"status": "passed", "completed_at": "2026-09-20T00:00:00Z", "evidence_url": f"https://evidence.example.test/{name}"} for name in ("backup_restore", "regional_failover", "load", "rollback")},
        "rollback": {"owner": "incident-commander", "deadline_minutes": 15, "target_revision": "b" * 40, "triggers": ["error rate above 2%", "p95 latency above 2s"], "tested_at": "2026-09-20T00:00:00Z"},
    }
    manifest_path = work / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, sort_keys=True), encoding="utf-8")
    manifest_sha = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
    ledger = {"schema_version": 1, "revision": revision, "completed": []}
    for index, root in enumerate(roots):
        applied_at = f"2026-10-02T00:{index:02d}:00Z"
        verified_at = f"2026-10-02T00:{index + 10:02d}:00Z"
        plan_sha = format(index + 1, "x") * 64
        receipt = {
            "schema_version": 1,
            "root": root,
            "revision": revision,
            "account_id": account_id,
            "applied_plan_sha256": plan_sha,
            "manifest_sha256": manifest_sha,
            "verified_at": verified_at,
            "checks": [f"production-{root} live state is healthy"],
        }
        path = receipts / f"production-{root}-verification.json"
        path.write_text(json.dumps(receipt, sort_keys=True), encoding="utf-8")
        ledger["completed"].append(
            {
                "root": root,
                "revision": revision,
                "sha256": plan_sha,
                "manifest_sha256": manifest_sha,
                "applied_at": applied_at,
                "verified_at": verified_at,
                "receipt_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            }
        )
    snapshot = {
        "runtime": {"version": "123e4567-e89b-42d3-a456-426614174000", "revision": revision, "builtAt": "2026-10-01T12:00:00Z", "environment": "production"},
        "runtime_headers": {"content-type": "application/json", "cache-control": "private, no-store"},
        "runtime_url": "https://www.logitrack.kr/api/runtime-version",
        "home_contains_brand": True,
        "home_headers": {"strict-transport-security": "max-age=31536000; includeSubDomains", "content-security-policy": "default-src 'self'; frame-ancestors 'none'"},
        "home_url": "https://www.logitrack.kr/",
        "alarms": {
            "ap-northeast-2": [{"name": name, "state": "OK", "state_updated_at": "2026-10-02T00:40:00Z"} for name in regional_alarms],
            "us-east-1": [{"name": name, "state": "OK", "state_updated_at": "2026-10-02T00:40:00+00:00"} for name in global_alarms],
        },
    }
    ledger_path = work / "ledger.json"
    snapshot_path = work / "snapshot.json"
    completion_path = work / "completion.json"

    def invoke(candidate_ledger, candidate_snapshot, output):
        ledger_path.write_text(json.dumps(candidate_ledger, sort_keys=True), encoding="utf-8")
        snapshot_path.write_text(json.dumps(candidate_snapshot), encoding="utf-8")
        return subprocess.run(
            [sys.executable, str(validator), "--ledger", str(ledger_path), "--manifest", str(manifest_path), "--receipt-dir", str(receipts), "--completion-receipt", str(output), "--revision", revision, "--account-id", account_id, "--snapshot", str(snapshot_path), "--now", now],
            capture_output=True,
            text=True,
        )

    accepted = invoke(deepcopy(ledger), deepcopy(snapshot), completion_path)
    assert accepted.returncode == 0, accepted.stderr
    completion = json.loads(completion_path.read_text(encoding="utf-8"))
    assert completion["ledger_sha256"] == hashlib.sha256(ledger_path.read_bytes()).hexdigest()
    assert completion["manifest_sha256"] == manifest_sha
    assert [item["root"] for item in completion["root_receipts"]] == roots
    assert completion["public_verification"]["revision"] == revision
    assert completion["alarm_verification"]["required_alarm_count"] == 24
    assert completion["alarm_verification"]["minimum_ok_minutes"] == 10
    assert completion["alarm_verification"]["region_counts"] == {"ap-northeast-2": 21, "us-east-1": 3}

    rejected_overwrite = invoke(deepcopy(ledger), deepcopy(snapshot), completion_path)
    assert rejected_overwrite.returncode == 1 and "already exists" in rejected_overwrite.stderr

    incomplete = deepcopy(ledger)
    incomplete["completed"].pop()
    rejected_incomplete = invoke(incomplete, snapshot, work / "incomplete.json")
    assert rejected_incomplete.returncode == 1 and "not complete" in rejected_incomplete.stderr

    wrong_runtime = deepcopy(snapshot)
    wrong_runtime["runtime"]["revision"] = "b" * 40
    rejected_runtime = invoke(ledger, wrong_runtime, work / "wrong-runtime.json")
    assert rejected_runtime.returncode == 1 and "runtime revision" in rejected_runtime.stderr

    missing_alarm = deepcopy(snapshot)
    missing_alarm["alarms"]["us-east-1"].pop()
    rejected_missing_alarm = invoke(ledger, missing_alarm, work / "missing-alarm.json")
    assert rejected_missing_alarm.returncode == 1 and "alarms are missing" in rejected_missing_alarm.stderr

    firing_alarm = deepcopy(snapshot)
    firing_alarm["alarms"]["ap-northeast-2"][0]["state"] = "ALARM"
    rejected_firing_alarm = invoke(ledger, firing_alarm, work / "firing-alarm.json")
    assert rejected_firing_alarm.returncode == 1 and "is not OK" in rejected_firing_alarm.stderr

    insufficient_alarm = deepcopy(snapshot)
    insufficient_alarm["alarms"]["ap-northeast-2"][1]["state"] = "INSUFFICIENT_DATA"
    rejected_insufficient_alarm = invoke(ledger, insufficient_alarm, work / "insufficient-alarm.json")
    assert rejected_insufficient_alarm.returncode == 1 and "INSUFFICIENT_DATA" in rejected_insufficient_alarm.stderr

    recent_alarm = deepcopy(snapshot)
    recent_alarm["alarms"]["us-east-1"][0]["state_updated_at"] = "2026-10-02T00:55:00Z"
    rejected_recent_alarm = invoke(ledger, recent_alarm, work / "recent-alarm.json")
    assert rejected_recent_alarm.returncode == 1 and "remained OK for 10 minutes" in rejected_recent_alarm.stderr

    state_path = receipts / "production-state-verification.json"
    original = state_path.read_text(encoding="utf-8")
    state_path.write_text(original + " ", encoding="utf-8")
    rejected_tamper = invoke(ledger, snapshot, work / "tampered.json")
    assert rejected_tamper.returncode == 1 and "digest" in rejected_tamper.stderr

source = validator.read_text(encoding="utf-8")
for contract in ("get-caller-identity", "describe-alarms", "MINIMUM_ALARM_OK_AGE", "TLSv1_2", "www.logitrack.kr/api/runtime-version", "completion receipt already exists", "receipt_sha256"):
    assert contract in source, f"completion gate is missing: {contract}"

print("PASS: production cutover completion binds all receipts, public runtime, and a ten-minute CloudWatch alarm soak")
