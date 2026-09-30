import hashlib
import json
import subprocess
import sys
import tempfile
from copy import deepcopy
from pathlib import Path


repo = Path(__file__).resolve().parents[1]
verifier = repo / "scripts/production-post-apply-verify.py"
revision = "a" * 40
account_id = "123456789012"
now = "2026-10-02T01:00:00Z"
state_keys = [
    "production/alerting/terraform.tfstate",
    "production/audit/terraform.tfstate",
    "production/certificates/terraform.tfstate",
    "production/data/terraform.tfstate",
    "production/compute/terraform.tfstate",
    "production/edge/terraform.tfstate",
]


def terraform_output(value):
    return {"sensitive": False, "type": "dynamic", "value": value}


with tempfile.TemporaryDirectory() as directory:
    work = Path(directory)
    ledger_path = work / "ledger.json"
    receipt_path = work / "state-receipt.json"
    snapshot_path = work / "state-snapshot.json"
    ledger = {
        "schema_version": 1,
        "revision": revision,
        "completed": [{"root": "state", "revision": revision, "sha256": "b" * 64, "manifest_sha256": "c" * 64, "applied_at": "2026-10-02T00:30:00Z"}],
    }
    snapshot = {
        "outputs": {"state_keys": terraform_output(state_keys)},
        "observations": {
            "versioning": "Enabled",
            "public_access_block": {"BlockPublicAcls": True, "IgnorePublicAcls": True, "BlockPublicPolicy": True, "RestrictPublicBuckets": True},
            "kms_rotation": True,
        },
    }

    def invoke(candidate_ledger, candidate_snapshot, receipt=receipt_path):
        ledger_path.write_text(json.dumps(candidate_ledger), encoding="utf-8")
        snapshot_path.write_text(json.dumps(candidate_snapshot), encoding="utf-8")
        return subprocess.run(
            [sys.executable, str(verifier), "--root", "state", "--revision", revision, "--account-id", account_id, "--ledger", str(ledger_path), "--receipt", str(receipt), "--snapshot", str(snapshot_path), "--now", now],
            capture_output=True,
            text=True,
        )

    accepted = invoke(deepcopy(ledger), deepcopy(snapshot))
    assert accepted.returncode == 0, accepted.stderr
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    updated = json.loads(ledger_path.read_text(encoding="utf-8"))
    entry = updated["completed"][0]
    assert receipt["checks"] and receipt["account_id"] == account_id
    assert entry["verified_at"] == now
    assert entry["receipt_sha256"] == hashlib.sha256(receipt_path.read_bytes()).hexdigest()

    bad_snapshot = deepcopy(snapshot)
    bad_snapshot["observations"]["versioning"] = "Suspended"
    failed_receipt = work / "failed-receipt.json"
    rejected = invoke(deepcopy(ledger), bad_snapshot, failed_receipt)
    assert rejected.returncode == 1 and "versioning" in rejected.stderr
    assert not failed_receipt.exists()
    assert "verified_at" not in json.loads(ledger_path.read_text(encoding="utf-8"))["completed"][0]

    out_of_order = deepcopy(ledger)
    out_of_order["completed"].append({"root": "alerting", "revision": revision, "sha256": "d" * 64, "manifest_sha256": "e" * 64, "applied_at": "2026-10-02T00:45:00Z"})
    rejected_order = invoke(out_of_order, snapshot, work / "order-receipt.json")
    assert rejected_order.returncode == 1 and "most recently applied root" in rejected_order.stderr

source = verifier.read_text(encoding="utf-8")
for command in ("get-caller-identity", "get-bucket-versioning", "get-trail-status", "describe-certificate", "describe-db-instances", "describe-replication-groups", "describe-cluster-v2", "describe-services", "describe-target-health", "describe-load-balancers", "get-distribution"):
    assert command in source, f"live verifier is missing: {command}"

print("PASS: post-apply verification records a hashed receipt only after live-state checks and rejects unhealthy or out-of-order state")
