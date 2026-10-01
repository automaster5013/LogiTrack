#!/usr/bin/env python3
import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse


SHA = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
ACTOR = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._@-]{2,127}$")
REPOSITORY = Path(__file__).resolve().parents[1]
ORDER = ["state", "alerting", "audit", "certificates", "data", "compute", "edge"]


def load(path: Path, label: str) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read {label}: {exc}") from exc
    if not isinstance(value, dict):
        raise ValueError(f"{label} root must be an object")
    return value


def digest(path: Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError as exc:
        raise ValueError(f"cannot hash {path}: {exc}") from exc


def atomic_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")
        temporary = Path(stream.name)
    temporary.replace(path)


def https_url(value: str) -> bool:
    parsed = urlparse(value)
    return parsed.scheme == "https" and bool(parsed.netloc) and not parsed.username and not parsed.password


def main() -> int:
    parser = argparse.ArgumentParser(description="Declare and evidence a production cutover rollback fence.")
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--ledger", required=True, type=Path)
    parser.add_argument("--receipt", required=True, type=Path)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--trigger", required=True)
    parser.add_argument("--evidence-url", required=True)
    parser.add_argument("--actor", required=True)
    parser.add_argument("--confirmation", required=True)
    parser.add_argument("--now", help="Test-only RFC3339 UTC clock")
    args = parser.parse_args()
    try:
        if not SHA.fullmatch(args.revision):
            raise ValueError("revision must be a lowercase 40-character commit SHA")
        if args.now and args.revision != "a" * 40:
            raise ValueError("--now is restricted to the fixed smoke-test revision")
        if args.confirmation != f"ROLLBACK {args.revision}":
            raise ValueError(f"confirmation must exactly equal: ROLLBACK {args.revision}")
        if not ACTOR.fullmatch(args.actor):
            raise ValueError("actor must be a stable 3..128 character operator identity")
        if not https_url(args.evidence_url):
            raise ValueError("evidence URL must use HTTPS without embedded credentials")
        if args.receipt.exists():
            raise ValueError("rollback receipt already exists; receipts are immutable")

        preflight = [sys.executable, str(REPOSITORY / "scripts/production-cutover-preflight.py"), str(args.manifest), "--revision", args.revision, "--phase", "rollback"]
        if args.now:
            preflight.extend(["--now", args.now])
        checked = subprocess.run(preflight, check=False, capture_output=True, text=True)
        if checked.returncode != 0:
            raise ValueError(f"cutover manifest rejected: {checked.stderr.removeprefix('FAIL: ').strip()}")

        manifest = load(args.manifest, "cutover manifest")
        triggers = manifest.get("rollback", {}).get("triggers", [])
        if args.trigger not in triggers:
            raise ValueError("trigger must exactly match an approved manifest rollback trigger")
        ledger = load(args.ledger, "apply ledger")
        completed = ledger.get("completed")
        if ledger.get("schema_version") != 1 or ledger.get("revision") != args.revision or not isinstance(completed, list) or not completed:
            raise ValueError("rollback requires a valid ledger with at least one applied root")
        if ledger.get("rollback"):
            raise ValueError("rollback has already been declared")
        manifest_sha = digest(args.manifest)
        if [item.get("root") for item in completed if isinstance(item, dict)] != ORDER[: len(completed)]:
            raise ValueError("apply ledger is not an exact prefix of the required root order")
        if any(not isinstance(item, dict) or item.get("revision") != args.revision or item.get("manifest_sha256") != manifest_sha or not SHA256.fullmatch(str(item.get("sha256", ""))) or not str(item.get("applied_at", "")).endswith("Z") for item in completed):
            raise ValueError("apply ledger is not bound to the approved manifest")

        initiated_at = args.now or datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
        receipt = {
            "schema_version": 1,
            "revision": args.revision,
            "manifest_sha256": manifest_sha,
            "ledger_sha256_before_fence": digest(args.ledger),
            "applied_roots": [item.get("root") for item in completed],
            "trigger": args.trigger,
            "evidence_url": args.evidence_url,
            "actor": args.actor,
            "initiated_at": initiated_at,
            "rollback_deadline_minutes": manifest["rollback"]["deadline_minutes"],
            "rollback_owner": manifest["rollback"]["owner"],
            "target_revision": manifest["rollback"]["target_revision"],
        }
        atomic_json(args.receipt, receipt)
        ledger["rollback"] = {
            "initiated_at": initiated_at,
            "trigger": args.trigger,
            "actor": args.actor,
            "receipt_sha256": digest(args.receipt),
        }
        atomic_json(args.ledger, ledger)
        print(f"PASS: rollback fence declared; stop all forward apply and completion activity ({ledger['rollback']['receipt_sha256']})")
        return 0
    except (ValueError, TypeError, KeyError, subprocess.SubprocessError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
