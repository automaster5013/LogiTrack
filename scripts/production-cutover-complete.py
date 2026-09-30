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


REPOSITORY = Path(__file__).resolve().parents[1]
ORDER = ["state", "alerting", "audit", "certificates", "data", "compute", "edge"]
SHA = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
ACCOUNT = re.compile(r"^[0-9]{12}$")


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
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError(f"{label} must be an RFC3339 UTC timestamp") from exc
    return parsed.astimezone(timezone.utc)


def atomic_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")
        temporary = Path(stream.name)
    temporary.replace(path)


def live_observations(account_id: str, url: str) -> dict:
    identity = subprocess.run(
        ["aws", "--region", "ap-northeast-2", "sts", "get-caller-identity", "--output", "json"],
        check=False,
        capture_output=True,
        text=True,
    )
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
    request = urllib.request.Request(url, headers={"User-Agent": "LogiTrack-production-cutover/1"})
    try:
        with urllib.request.urlopen(request, timeout=20, context=context) as response:
            runtime = json.loads(response.read().decode("utf-8"))
            runtime_headers = {name.lower(): value for name, value in response.headers.items()}
            runtime_url = response.geturl()
        home_request = urllib.request.Request(url.removesuffix("/api/runtime-version") + "/", headers={"User-Agent": "LogiTrack-production-cutover/1"})
        with urllib.request.urlopen(home_request, timeout=20, context=context) as response:
            home = response.read().decode("utf-8")
            home_headers = {name.lower(): value for name, value in response.headers.items()}
            home_url = response.geturl()
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"public HTTPS verification failed: {exc}") from exc
    return {"runtime": runtime, "runtime_headers": runtime_headers, "runtime_url": runtime_url, "home_contains_brand": "LIVE LOGISTICS INTELLIGENCE" in home, "home_headers": home_headers, "home_url": home_url}


def validate_public(observations: dict, revision: str, environment: str, now: datetime) -> dict:
    runtime = observations.get("runtime", {})
    if not isinstance(runtime, dict) or runtime.get("revision") != revision or runtime.get("environment") != environment:
        raise ValueError("public runtime revision or environment does not match the approved cutover")
    try:
        parsed_version = uuid.UUID(str(runtime.get("version")))
        if parsed_version.version != 4:
            raise ValueError("not UUIDv4")
    except (ValueError, AttributeError) as exc:
        raise ValueError("public runtime version is not a UUIDv4") from exc
    built_at = timestamp(runtime.get("builtAt"), "public runtime builtAt")
    if built_at > now or now - built_at > timedelta(days=7):
        raise ValueError("public runtime build is future-dated or older than seven days")
    runtime_headers = observations.get("runtime_headers", {})
    home_headers = observations.get("home_headers", {})
    if not isinstance(runtime_headers, dict) or not isinstance(home_headers, dict):
        raise ValueError("public response headers are malformed")
    if observations.get("runtime_url") != "https://www.logitrack.kr/api/runtime-version" or observations.get("home_url") != "https://www.logitrack.kr/":
        raise ValueError("public verification was redirected away from canonical endpoints")
    if "application/json" not in str(runtime_headers.get("content-type", "")).lower() or "no-store" not in str(runtime_headers.get("cache-control", "")).lower():
        raise ValueError("public runtime metadata must be JSON and non-cacheable")
    if observations.get("home_contains_brand") is not True:
        raise ValueError("public home page brand marker is missing")
    if "max-age=31536000" not in str(home_headers.get("strict-transport-security", "")) or "default-src 'self'" not in str(home_headers.get("content-security-policy", "")):
        raise ValueError("public home page security headers are incomplete")
    return {"url": "https://www.logitrack.kr/api/runtime-version", "version": runtime["version"], "revision": revision, "environment": environment, "built_at": runtime["builtAt"]}


def main() -> int:
    parser = argparse.ArgumentParser(description="Finalize a production cutover from all root receipts and public live state.")
    parser.add_argument("--ledger", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--receipt-dir", required=True, type=Path)
    parser.add_argument("--completion-receipt", required=True, type=Path)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--account-id", required=True)
    parser.add_argument("--expected-environment", default="production")
    parser.add_argument("--url", default="https://www.logitrack.kr/api/runtime-version")
    parser.add_argument("--snapshot", type=Path, help="Test-only public observation JSON")
    parser.add_argument("--now", help="Test-only RFC3339 UTC clock")
    args = parser.parse_args()
    try:
        if not SHA.fullmatch(args.revision) or not ACCOUNT.fullmatch(args.account_id):
            raise ValueError("revision or AWS account ID is invalid")
        if args.url != "https://www.logitrack.kr/api/runtime-version":
            raise ValueError("public verification URL must be the canonical HTTPS endpoint")
        if args.expected_environment != "production":
            raise ValueError("cutover completion requires the production environment")
        if args.completion_receipt.exists():
            raise ValueError("completion receipt already exists; receipts are immutable")
        if bool(args.snapshot) != bool(args.now):
            raise ValueError("test mode requires both --snapshot and --now")
        if args.snapshot and (args.revision != "a" * 40 or args.account_id != "123456789012" or args.expected_environment != "production"):
            raise ValueError("test snapshots are restricted to the fixed smoke-test identity")
        now = timestamp(args.now, "now") if args.now else datetime.now(timezone.utc)
        preflight = [sys.executable, str(REPOSITORY / "scripts/production-cutover-preflight.py"), str(args.manifest), "--revision", args.revision, "--phase", "apply"]
        if args.now:
            preflight.extend(["--now", args.now])
        preflight_result = subprocess.run(preflight, check=False, capture_output=True, text=True)
        if preflight_result.returncode != 0:
            raise ValueError(f"cutover manifest rejected: {preflight_result.stderr.removeprefix('FAIL: ').strip()}")
        manifest_sha = digest(args.manifest)
        ledger = load(args.ledger, "apply ledger")
        completed = ledger.get("completed")
        if ledger.get("schema_version") != 1 or ledger.get("revision") != args.revision or not isinstance(completed, list) or [item.get("root") for item in completed if isinstance(item, dict)] != ORDER:
            raise ValueError("apply ledger is not complete for all seven roots")

        receipts = []
        for entry, root in zip(completed, ORDER):
            receipt_path = args.receipt_dir / f"production-{root}-verification.json"
            receipt_sha = digest(receipt_path)
            receipt = load(receipt_path, f"production-{root} receipt")
            if entry.get("revision") != args.revision or not SHA256.fullmatch(str(entry.get("sha256", ""))) or entry.get("manifest_sha256") != manifest_sha:
                raise ValueError(f"production-{root} ledger entry is malformed")
            if receipt.get("schema_version") != 1 or entry.get("receipt_sha256") != receipt_sha or receipt.get("root") != root or receipt.get("revision") != args.revision or receipt.get("account_id") != args.account_id:
                raise ValueError(f"production-{root} receipt identity or digest does not match the ledger")
            if receipt.get("applied_plan_sha256") != entry.get("sha256") or receipt.get("manifest_sha256") != entry.get("manifest_sha256") or receipt.get("verified_at") != entry.get("verified_at"):
                raise ValueError(f"production-{root} receipt does not match its applied evidence")
            verified_at = timestamp(entry.get("verified_at"), f"production-{root} verified_at")
            if verified_at < timestamp(entry.get("applied_at"), f"production-{root} applied_at") or verified_at > now:
                raise ValueError(f"production-{root} verification time is outside the valid apply-to-completion window")
            if not isinstance(receipt.get("checks"), list) or not receipt["checks"] or not all(isinstance(item, str) and item for item in receipt["checks"]):
                raise ValueError(f"production-{root} receipt has no completed checks")
            receipts.append({"root": root, "sha256": receipt_sha, "verified_at": entry["verified_at"]})

        observations = load(args.snapshot, "public verification snapshot") if args.snapshot else live_observations(args.account_id, args.url)
        public = validate_public(observations, args.revision, args.expected_environment, now)
        completion = {"schema_version": 1, "revision": args.revision, "account_id": args.account_id, "completed_at": now.isoformat().replace("+00:00", "Z"), "manifest_sha256": manifest_sha, "ledger_sha256": digest(args.ledger), "root_receipts": receipts, "public_verification": public}
        atomic_json(args.completion_receipt, completion)
        print(f"PASS: production cutover completion receipt recorded ({digest(args.completion_receipt)})")
        return 0
    except (ValueError, TypeError, KeyError, subprocess.SubprocessError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
