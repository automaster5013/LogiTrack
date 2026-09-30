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
        "rollback": {"owner": "incident-commander", "deadline_minutes": 15, "triggers": ["error rate above 2%", "p95 latency above 2s"], "tested_at": "2026-09-20T00:00:00Z"},
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

    state_path = receipts / "production-state-verification.json"
    original = state_path.read_text(encoding="utf-8")
    state_path.write_text(original + " ", encoding="utf-8")
    rejected_tamper = invoke(ledger, snapshot, work / "tampered.json")
    assert rejected_tamper.returncode == 1 and "digest" in rejected_tamper.stderr

source = validator.read_text(encoding="utf-8")
for contract in ("get-caller-identity", "TLSv1_2", "www.logitrack.kr/api/runtime-version", "completion receipt already exists", "receipt_sha256"):
    assert contract in source, f"completion gate is missing: {contract}"

print("PASS: production cutover completion binds all seven receipts to the ledger and verified public runtime state")
