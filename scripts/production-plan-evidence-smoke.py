import json
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
validator = root / "scripts/production-plan-evidence.py"

with tempfile.TemporaryDirectory() as directory:
    work = Path(directory)
    plan_file = work / "plan.tfplan"
    plan_json = work / "plan.json"
    evidence = work / "evidence.json"
    plan_file.write_bytes(b"opaque terraform plan\x00")
    base = {
        "format_version": "1.2",
        "terraform_version": "1.16.3",
        "resource_changes": [
            {"address": "aws_s3_bucket.example", "change": {"actions": ["create"]}},
            {"address": "aws_kms_key.example", "change": {"actions": ["update"]}},
        ],
    }

    def run(payload):
        plan_json.write_text(json.dumps(payload), encoding="utf-8")
        return subprocess.run(
            [sys.executable, str(validator), "--plan-json", str(plan_json), "--plan-file", str(plan_file), "--root", "audit", "--revision", "a" * 40, "--output", str(evidence), "--generated-at", "2026-10-01T00:00:00Z"],
            capture_output=True,
            text=True,
        )

    valid = run(base)
    assert valid.returncode == 0, valid.stderr
    result = json.loads(evidence.read_text())
    assert result["destructive_changes"] is False
    assert result["resource_action_counts"] == {"create": 1, "no_op": 0, "read": 0, "update": 1}
    assert len(result["sha256"]) == 64
    assert "resource_changes" not in result

    destructive = json.loads(json.dumps(base))
    destructive["resource_changes"][0]["change"]["actions"] = ["delete", "create"]
    rejected = run(destructive)
    assert rejected.returncode == 1
    assert "destructive resource actions detected" in rejected.stderr

print("PASS: production plan evidence is sanitized, digest-bound, and rejects destructive actions")
