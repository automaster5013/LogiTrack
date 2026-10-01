import hashlib
import json
import subprocess
import sys
import tempfile
from copy import deepcopy
from pathlib import Path


repo = Path(__file__).resolve().parents[1]
rollback = repo / "scripts/production-cutover-rollback.py"
apply_guard = repo / "scripts/production-apply-guard.py"
post_verify = repo / "scripts/production-post-apply-verify.py"
complete = repo / "scripts/production-cutover-complete.py"
rollback_complete = repo / "scripts/production-cutover-rollback-complete.py"
revision = "a" * 40
now = "2026-10-02T01:00:00Z"
account_id = "123456789012"
roots = ["state", "alerting", "audit", "certificates", "data", "compute", "edge"]


with tempfile.TemporaryDirectory() as directory:
    work = Path(directory)
    plan = work / "plan.tfplan"
    plan.write_bytes(b"approved alerting plan")
    plan_sha = hashlib.sha256(plan.read_bytes()).hexdigest()
    plans = {f"production-{root}": {"revision": revision, "sha256": plan_sha, "destructive_changes": False, "planned_at": "2026-10-01T12:00:00Z"} for root in roots}
    triggers = ["error rate above 2%", "p95 latency above 2s"]
    manifest = {
        "schema_version": 1,
        "revision": revision,
        "change_ticket_url": "https://changes.example.test/LOGI-45",
        "approvals": [{"role": role, "actor": f"{role}-owner", "approved_at": "2026-09-30T12:00:00Z"} for role in ("business", "security", "operations")],
        "window": {"start": "2026-10-02T00:00:00Z", "end": "2026-10-02T02:00:00Z"},
        "terraform_plans": plans,
        "readiness": {"regional_paging_subscription": "confirmed", "global_paging_subscription": "confirmed", "origin_certificate": "issued", "viewer_certificate": "issued", "dns_ttl_seconds": 60},
        "drills": {name: {"status": "passed", "completed_at": "2026-09-20T00:00:00Z", "evidence_url": f"https://evidence.example.test/{name}"} for name in ("backup_restore", "regional_failover", "load", "rollback")},
        "rollback": {"owner": "incident-commander", "deadline_minutes": 15, "target_revision": "b" * 40, "triggers": triggers, "tested_at": "2026-09-20T00:00:00Z"},
    }
    manifest_path = work / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, sort_keys=True), encoding="utf-8")
    manifest_sha = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
    ledger = {"schema_version": 1, "revision": revision, "completed": [{"root": "state", "revision": revision, "sha256": plan_sha, "manifest_sha256": manifest_sha, "applied_at": "2026-10-02T00:30:00Z"}]}
    ledger_path = work / "ledger.json"
    ledger_path.write_text(json.dumps(ledger, sort_keys=True), encoding="utf-8")
    receipt_path = work / "rollback.json"

    command = [sys.executable, str(rollback), "--manifest", str(manifest_path), "--ledger", str(ledger_path), "--receipt", str(receipt_path), "--revision", revision, "--trigger", triggers[0], "--evidence-url", "https://evidence.example.test/incident/45", "--actor", "oncall@example.test", "--confirmation", f"ROLLBACK {revision}", "--now", now]
    bad_command = command.copy()
    bad_command[bad_command.index(triggers[0])] = "operator intuition"
    bad_command[bad_command.index(str(receipt_path))] = str(work / "rejected.json")
    rejected_trigger = subprocess.run(bad_command, capture_output=True, text=True)
    assert rejected_trigger.returncode == 1 and "approved manifest rollback trigger" in rejected_trigger.stderr

    accepted = subprocess.run(command, capture_output=True, text=True)
    assert accepted.returncode == 0, accepted.stderr
    fenced = json.loads(ledger_path.read_text(encoding="utf-8"))
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    assert fenced["rollback"]["receipt_sha256"] == hashlib.sha256(receipt_path.read_bytes()).hexdigest()
    assert receipt["ledger_sha256_before_fence"] == hashlib.sha256(json.dumps(ledger, sort_keys=True).encode("utf-8")).hexdigest()
    assert receipt["trigger"] == triggers[0] and receipt["rollback_deadline_minutes"] == 15
    assert receipt["target_revision"] == "b" * 40

    duplicate = subprocess.run(command, capture_output=True, text=True)
    assert duplicate.returncode == 1 and "already exists" in duplicate.stderr

    evidence_path = work / "evidence.json"
    evidence_path.write_text(json.dumps({"schema_version": 1, "root": "production-alerting", **plans["production-alerting"]}), encoding="utf-8")
    blocked_apply = subprocess.run([sys.executable, str(apply_guard), "--manifest", str(manifest_path), "--evidence", str(evidence_path), "--plan-file", str(plan), "--ledger", str(ledger_path), "--root", "alerting", "--revision", revision, "--now", now], capture_output=True, text=True)
    assert blocked_apply.returncode == 1 and "rollback fence is active" in blocked_apply.stderr

    snapshot_path = work / "snapshot.json"
    snapshot_path.write_text(json.dumps({"outputs": {}, "observations": {}}), encoding="utf-8")
    blocked_verify = subprocess.run([sys.executable, str(post_verify), "--root", "state", "--revision", revision, "--account-id", account_id, "--ledger", str(ledger_path), "--receipt", str(work / "post.json"), "--snapshot", str(snapshot_path), "--now", now], capture_output=True, text=True)
    assert blocked_verify.returncode == 1 and "rollback fence is active" in blocked_verify.stderr

    blocked_completion = subprocess.run([sys.executable, str(complete), "--manifest", str(manifest_path), "--ledger", str(ledger_path), "--receipt-dir", str(work), "--completion-receipt", str(work / "completion.json"), "--revision", revision, "--account-id", account_id, "--snapshot", str(snapshot_path), "--now", now], capture_output=True, text=True)
    assert blocked_completion.returncode == 1 and "rollback fence is active" in blocked_completion.stderr

    recovery_snapshot = {
        "runtime": {"version": "123e4567-e89b-42d3-a456-426614174000", "revision": "b" * 40, "builtAt": "2026-09-20T00:00:00Z", "environment": "production"},
        "runtime_headers": {"content-type": "application/json", "cache-control": "private, no-store"},
        "runtime_url": "https://www.logitrack.kr/api/runtime-version",
        "home_contains_brand": True,
        "home_headers": {"strict-transport-security": "max-age=31536000; includeSubDomains", "content-security-policy": "default-src 'self'; frame-ancestors 'none'"},
        "home_url": "https://www.logitrack.kr/",
    }
    recovery_snapshot_path = work / "recovery-snapshot.json"
    recovery_snapshot_path.write_text(json.dumps(recovery_snapshot), encoding="utf-8")
    rollback_completion_path = work / "rollback-completion.json"
    completion_command = [sys.executable, str(rollback_complete), "--manifest", str(manifest_path), "--ledger", str(ledger_path), "--rollback-receipt", str(receipt_path), "--completion-receipt", str(rollback_completion_path), "--revision", revision, "--account-id", account_id, "--snapshot", str(recovery_snapshot_path), "--now", now]

    wrong_recovery = deepcopy(recovery_snapshot)
    wrong_recovery["runtime"]["revision"] = "c" * 40
    recovery_snapshot_path.write_text(json.dumps(wrong_recovery), encoding="utf-8")
    rejected_recovery = subprocess.run(completion_command, capture_output=True, text=True)
    assert rejected_recovery.returncode == 1 and "approved production target revision" in rejected_recovery.stderr
    assert not rollback_completion_path.exists()

    late_command = completion_command.copy()
    late_command[late_command.index(str(rollback_completion_path))] = str(work / "late-completion.json")
    late_command[late_command.index(now)] = "2026-10-02T01:16:00Z"
    recovery_snapshot_path.write_text(json.dumps(recovery_snapshot), encoding="utf-8")
    rejected_late = subprocess.run(late_command, capture_output=True, text=True)
    assert rejected_late.returncode == 1 and "approved deadline" in rejected_late.stderr

    recovery_snapshot_path.write_text(json.dumps(recovery_snapshot), encoding="utf-8")
    recovered = subprocess.run(completion_command, capture_output=True, text=True)
    assert recovered.returncode == 0, recovered.stderr
    completed_ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
    assert completed_ledger["rollback"]["target_revision"] == "b" * 40
    assert completed_ledger["rollback"]["completion_receipt_sha256"] == hashlib.sha256(rollback_completion_path.read_bytes()).hexdigest()

    duplicate_completion = subprocess.run(completion_command, capture_output=True, text=True)
    assert duplicate_completion.returncode == 1 and "already exists" in duplicate_completion.stderr

print("PASS: rollback declaration fences forward paths and completion verifies recovery to the pre-approved runtime revision")
