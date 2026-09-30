import json
import subprocess
import sys
import tempfile
from copy import deepcopy
from pathlib import Path

root = Path(__file__).resolve().parents[1]
validator = root / "scripts/production-cutover-preflight.py"
revision = "a" * 40
now = "2026-10-01T18:00:00Z"
roots = ["production-state", "production-alerting", "production-audit", "production-certificates", "production-data", "production-compute", "production-edge"]
manifest = {
    "schema_version": 1,
    "revision": revision,
    "change_ticket_url": "https://changes.example.test/LOGI-42",
    "approvals": [{"role": role, "actor": f"{role}-owner", "approved_at": "2026-09-30T12:00:00Z"} for role in ["business", "security", "operations"]],
    "window": {"start": "2026-10-02T00:00:00Z", "end": "2026-10-02T02:00:00Z"},
    "terraform_plans": {name: {"revision": revision, "sha256": str(index) * 64, "destructive_changes": False, "planned_at": "2026-10-01T12:00:00Z"} for index, name in enumerate(roots, 1)},
    "readiness": {"regional_paging_subscription": "confirmed", "global_paging_subscription": "confirmed", "origin_certificate": "issued", "viewer_certificate": "issued", "dns_ttl_seconds": 60},
    "drills": {name: {"status": "passed", "completed_at": "2026-09-20T00:00:00Z", "evidence_url": f"https://evidence.example.test/{name}"} for name in ["backup_restore", "regional_failover", "load", "rollback"]},
    "rollback": {"owner": "incident-commander", "deadline_minutes": 15, "triggers": ["error rate above 2%", "p95 latency above 2s"], "tested_at": "2026-09-20T00:00:00Z"},
}

def run(payload, phase="prepare", clock=now):
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "manifest.json"
        path.write_text(json.dumps(payload), encoding="utf-8")
        return subprocess.run([sys.executable, str(validator), str(path), "--revision", revision, "--now", clock, "--phase", phase], capture_output=True, text=True)

valid = run(manifest)
assert valid.returncode == 0, valid.stderr
in_window = run(manifest, phase="apply", clock="2026-10-02T01:00:00Z")
assert in_window.returncode == 0, in_window.stderr
before_window = run(manifest, phase="apply", clock="2026-10-01T23:00:00Z")
assert before_window.returncode == 1 and "inside the approved cutover window" in before_window.stderr
after_window_rollback = run(manifest, phase="rollback", clock="2026-10-02T03:00:00Z")
assert after_window_rollback.returncode == 0, after_window_rollback.stderr
stale_rollback = run(manifest, phase="rollback", clock="2026-10-03T03:00:00Z")
assert stale_rollback.returncode == 1 and "24 hours" in stale_rollback.stderr
for mutate in ("destructive", "unconfirmed", "stale"):
    invalid = deepcopy(manifest)
    if mutate == "destructive": invalid["terraform_plans"]["production-data"]["destructive_changes"] = True
    if mutate == "unconfirmed": invalid["readiness"]["global_paging_subscription"] = "pending"
    if mutate == "stale": invalid["drills"]["load"]["completed_at"] = "2026-08-01T00:00:00Z"
    result = run(invalid)
    assert result.returncode == 1 and result.stderr.startswith("FAIL:"), (mutate, result.stdout, result.stderr)

print("PASS: production cutover gate accepts complete evidence and rejects destructive, unconfirmed, or stale inputs")
