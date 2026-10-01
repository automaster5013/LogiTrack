#!/usr/bin/env python3
import argparse
import hashlib
import json
import re
import ssl
import subprocess
import sys
import tempfile
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlparse


SHA = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
ACCOUNT = re.compile(r"^[0-9]{12}$")
REPOSITORY = Path(__file__).resolve().parents[1]
CANONICAL_URL = "https://www.logitrack.kr/api/runtime-version"


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


def timestamp(value: object, label: str) -> datetime:
    if not isinstance(value, str) or not value.endswith("Z"):
        raise ValueError(f"{label} must be an RFC3339 UTC timestamp")
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)
    except ValueError as exc:
        raise ValueError(f"{label} must be an RFC3339 UTC timestamp") from exc


def atomic_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")
        temporary = Path(stream.name)
    temporary.replace(path)


def live_observations(account_id: str) -> dict:
    identity = subprocess.run(["aws", "--region", "ap-northeast-2", "sts", "get-caller-identity", "--output", "json"], check=False, capture_output=True, text=True)
    if identity.returncode != 0:
        raise ValueError("AWS caller identity lookup failed")
    try:
        caller = json.loads(identity.stdout)
    except json.JSONDecodeError as exc:
        raise ValueError("AWS caller identity response is invalid") from exc
    if caller.get("Account") != account_id:
        raise ValueError("active AWS account does not match --account-id")

    context = ssl.create_default_context()
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    try:
        request = urllib.request.Request(CANONICAL_URL, headers={"User-Agent": "LogiTrack-production-rollback/1"})
        with urllib.request.urlopen(request, timeout=20, context=context) as response:
            runtime = json.loads(response.read().decode("utf-8"))
            runtime_headers = {name.lower(): value for name, value in response.headers.items()}
            runtime_url = response.geturl()
        home_request = urllib.request.Request("https://www.logitrack.kr/", headers={"User-Agent": "LogiTrack-production-rollback/1"})
        with urllib.request.urlopen(home_request, timeout=20, context=context) as response:
            home = response.read().decode("utf-8")
            home_headers = {name.lower(): value for name, value in response.headers.items()}
            home_url = response.geturl()
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"public rollback verification failed: {exc}") from exc
    return {"runtime": runtime, "runtime_headers": runtime_headers, "runtime_url": runtime_url, "home_contains_brand": "LIVE LOGISTICS INTELLIGENCE" in home, "home_headers": home_headers, "home_url": home_url}


def validate_public(observations: dict, target_revision: str, now: datetime) -> dict:
    runtime = observations.get("runtime", {})
    if not isinstance(runtime, dict) or runtime.get("revision") != target_revision or runtime.get("environment") != "production":
        raise ValueError("public runtime has not recovered to the approved production target revision")
    try:
        version = uuid.UUID(str(runtime.get("version")))
        if version.version != 4:
            raise ValueError("not UUIDv4")
    except (ValueError, AttributeError) as exc:
        raise ValueError("public runtime version is not a UUIDv4") from exc
    if timestamp(runtime.get("builtAt"), "public runtime builtAt") > now:
        raise ValueError("public runtime build is future-dated")
    runtime_headers = observations.get("runtime_headers", {})
    home_headers = observations.get("home_headers", {})
    if not isinstance(runtime_headers, dict) or not isinstance(home_headers, dict):
        raise ValueError("public response headers are malformed")
    if observations.get("runtime_url") != CANONICAL_URL or observations.get("home_url") != "https://www.logitrack.kr/":
        raise ValueError("public rollback verification was redirected away from canonical endpoints")
    if "application/json" not in str(runtime_headers.get("content-type", "")).lower() or "no-store" not in str(runtime_headers.get("cache-control", "")).lower():
        raise ValueError("public runtime metadata must be JSON and non-cacheable")
    if observations.get("home_contains_brand") is not True:
        raise ValueError("public home page brand marker is missing after rollback")
    if "max-age=31536000" not in str(home_headers.get("strict-transport-security", "")) or "default-src 'self'" not in str(home_headers.get("content-security-policy", "")):
        raise ValueError("public home page security headers are incomplete after rollback")
    return {"url": CANONICAL_URL, "version": runtime["version"], "revision": target_revision, "environment": "production", "built_at": runtime["builtAt"]}


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify public recovery and complete a fenced production rollback.")
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--ledger", required=True, type=Path)
    parser.add_argument("--rollback-receipt", required=True, type=Path)
    parser.add_argument("--completion-receipt", required=True, type=Path)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--account-id", required=True)
    parser.add_argument("--snapshot", type=Path, help="Test-only public observation JSON")
    parser.add_argument("--now", help="Test-only RFC3339 UTC clock")
    args = parser.parse_args()
    try:
        if not SHA.fullmatch(args.revision) or not ACCOUNT.fullmatch(args.account_id):
            raise ValueError("revision or AWS account ID is invalid")
        if args.completion_receipt.exists():
            raise ValueError("rollback completion receipt already exists; receipts are immutable")
        if bool(args.snapshot) != bool(args.now):
            raise ValueError("test mode requires both --snapshot and --now")
        if args.snapshot and (args.revision != "a" * 40 or args.account_id != "123456789012"):
            raise ValueError("test snapshots are restricted to the fixed smoke-test identity")
        now = timestamp(args.now, "now") if args.now else datetime.now(timezone.utc)
        preflight = [sys.executable, str(REPOSITORY / "scripts/production-cutover-preflight.py"), str(args.manifest), "--revision", args.revision, "--phase", "rollback"]
        if args.now:
            preflight.extend(["--now", args.now])
        checked = subprocess.run(preflight, check=False, capture_output=True, text=True)
        if checked.returncode != 0:
            raise ValueError(f"cutover manifest rejected: {checked.stderr.removeprefix('FAIL: ').strip()}")

        manifest = load(args.manifest, "cutover manifest")
        ledger = load(args.ledger, "apply ledger")
        rollback = ledger.get("rollback")
        receipt = load(args.rollback_receipt, "rollback receipt")
        receipt_sha = digest(args.rollback_receipt)
        manifest_sha = digest(args.manifest)
        if ledger.get("schema_version") != 1 or ledger.get("revision") != args.revision or not isinstance(rollback, dict):
            raise ValueError("an active rollback fence is required")
        if rollback.get("completion_receipt_sha256") or rollback.get("completed_at"):
            raise ValueError("rollback has already been completed")
        if rollback.get("receipt_sha256") != receipt_sha or receipt.get("schema_version") != 1 or receipt.get("revision") != args.revision or receipt.get("manifest_sha256") != manifest_sha:
            raise ValueError("rollback receipt identity or digest does not match the ledger")
        if not SHA256.fullmatch(str(receipt.get("ledger_sha256_before_fence", ""))):
            raise ValueError("rollback receipt pre-fence ledger digest is malformed")
        for field in ("initiated_at", "trigger", "actor"):
            if rollback.get(field) != receipt.get(field):
                raise ValueError(f"rollback receipt {field} does not match the ledger fence")
        evidence = urlparse(str(receipt.get("evidence_url", "")))
        if receipt.get("trigger") not in manifest["rollback"]["triggers"] or evidence.scheme != "https" or not evidence.netloc or evidence.username or evidence.password:
            raise ValueError("rollback trigger or HTTPS evidence is not approved")
        applied_roots = [item.get("root") for item in ledger.get("completed", []) if isinstance(item, dict)]
        if receipt.get("applied_roots") != applied_roots:
            raise ValueError("rollback receipt applied roots do not match the ledger")
        target_revision = manifest["rollback"]["target_revision"]
        if receipt.get("target_revision") != target_revision or receipt.get("rollback_deadline_minutes") != manifest["rollback"]["deadline_minutes"] or receipt.get("rollback_owner") != manifest["rollback"]["owner"]:
            raise ValueError("rollback receipt target, deadline, or owner does not match the manifest")
        initiated_at = timestamp(receipt.get("initiated_at"), "rollback initiated_at")
        deadline = initiated_at + timedelta(minutes=manifest["rollback"]["deadline_minutes"])
        if now < initiated_at or now > deadline:
            raise ValueError("rollback recovery was not verified inside the approved deadline")

        observations = load(args.snapshot, "rollback verification snapshot") if args.snapshot else live_observations(args.account_id)
        public = validate_public(observations, target_revision, now)
        completion = {"schema_version": 1, "revision": args.revision, "account_id": args.account_id, "completed_at": now.isoformat().replace("+00:00", "Z"), "manifest_sha256": manifest_sha, "ledger_sha256_before_completion": digest(args.ledger), "rollback_receipt_sha256": receipt_sha, "trigger": receipt["trigger"], "actor": receipt["actor"], "rollback_owner": receipt["rollback_owner"], "public_verification": public}
        atomic_json(args.completion_receipt, completion)
        rollback["completed_at"] = completion["completed_at"]
        rollback["target_revision"] = target_revision
        rollback["completion_receipt_sha256"] = digest(args.completion_receipt)
        atomic_json(args.ledger, ledger)
        print(f"PASS: production rollback recovered to {target_revision} and completion evidence was recorded")
        return 0
    except (ValueError, TypeError, KeyError, subprocess.SubprocessError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
