import hashlib
import json
import subprocess
import sys
import tempfile
from copy import deepcopy
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
guard = repo / "scripts/production-apply-guard.py"
revision = "a" * 40
now = "2026-10-02T01:00:00Z"
roots = ["state", "alerting", "audit", "certificates", "data", "compute", "edge"]

with tempfile.TemporaryDirectory() as directory:
    work = Path(directory)
    plan = work / "plan.tfplan"
    plan.write_bytes(b"reviewed opaque terraform plan\x00")
    digest = hashlib.sha256(plan.read_bytes()).hexdigest()
    plans = {
        f"production-{root}": {
            "revision": revision,
            "sha256": digest,
            "destructive_changes": False,
            "planned_at": "2026-10-01T12:00:00Z",
        }
        for root in roots
    }
    manifest = {
        "schema_version": 1,
        "revision": revision,
        "change_ticket_url": "https://changes.example.test/LOGI-43",
        "approvals": [{"role": role, "actor": f"{role}-owner", "approved_at": "2026-09-30T12:00:00Z"} for role in ["business", "security", "operations"]],
        "window": {"start": "2026-10-02T00:00:00Z", "end": "2026-10-02T02:00:00Z"},
        "terraform_plans": plans,
        "readiness": {"regional_paging_subscription": "confirmed", "global_paging_subscription": "confirmed", "origin_certificate": "issued", "viewer_certificate": "issued", "dns_ttl_seconds": 60},
        "drills": {name: {"status": "passed", "completed_at": "2026-09-20T00:00:00Z", "evidence_url": f"https://evidence.example.test/{name}"} for name in ["backup_restore", "regional_failover", "load", "rollback"]},
        "rollback": {"owner": "incident-commander", "deadline_minutes": 15, "triggers": ["error rate above 2%", "p95 latency above 2s"], "tested_at": "2026-09-20T00:00:00Z"},
    }
    manifest_path = work / "manifest.json"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    evidence_path = work / "evidence.json"
    ledger_path = work / "ledger.json"

    def invoke(root, evidence, candidate_plan=plan, ledger=ledger_path):
        evidence_path.write_text(json.dumps(evidence), encoding="utf-8")
        return subprocess.run(
            [sys.executable, str(guard), "--manifest", str(manifest_path), "--evidence", str(evidence_path), "--plan-file", str(candidate_plan), "--ledger", str(ledger), "--root", root, "--revision", revision, "--now", now],
            capture_output=True,
            text=True,
        )

    state_evidence = {"schema_version": 1, "root": "production-state", **plans["production-state"]}
    accepted = invoke("state", state_evidence)
    assert accepted.returncode == 0, accepted.stderr
    assert not ledger_path.exists(), "verification-only mode must not advance the ledger"

    out_of_order = {"schema_version": 1, "root": "production-data", **plans["production-data"]}
    rejected_order = invoke("data", out_of_order)
    assert rejected_order.returncode == 1 and "production-state next" in rejected_order.stderr

    corrupt = work / "corrupt.tfplan"
    corrupt.write_bytes(b"different plan")
    rejected_digest = invoke("state", state_evidence, corrupt)
    assert rejected_digest.returncode == 1 and "SHA-256" in rejected_digest.stderr

    mismatched = deepcopy(state_evidence)
    mismatched["planned_at"] = "2026-10-01T13:00:00Z"
    rejected_evidence = invoke("state", mismatched)
    assert rejected_evidence.returncode == 1 and "planned_at" in rejected_evidence.stderr

    ledger_path.write_text(json.dumps({"schema_version": 1, "revision": revision, "completed": [{"root": "state", "revision": revision, "sha256": digest, "manifest_sha256": "b" * 64, "applied_at": "2026-10-02T00:30:00Z"}]}), encoding="utf-8")
    alerting_evidence = {"schema_version": 1, "root": "production-alerting", **plans["production-alerting"]}
    accepted_next = invoke("alerting", alerting_evidence)
    assert accepted_next.returncode == 0, accepted_next.stderr

source = guard.read_text(encoding="utf-8")
assert "verify_git(args.revision)" in source
assert "if completed.returncode != 0:" in source
assert source.index("if completed.returncode != 0:") < source.index('ledger["completed"].append(')
assert '"apply", "-input=false", str(args.plan_file.resolve())' in source
assert "write_ledger(args.ledger, ledger)" in source

print("PASS: production apply guard binds manifest, evidence, plan digest, revision, window, and root order before execution")
