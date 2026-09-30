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

ORDER = ["state", "alerting", "audit", "certificates", "data", "compute", "edge"]
SHA = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
REPOSITORY = Path(__file__).resolve().parents[1]


def load_object(path: Path, label: str) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read {label}: {exc}") from exc
    if not isinstance(value, dict):
        raise ValueError(f"{label} root must be an object")
    return value


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise ValueError(f"cannot read plan file: {exc}") from exc
    return digest.hexdigest()


def validate_ledger(path: Path, revision: str) -> tuple[dict, str]:
    if not path.exists():
        return {"schema_version": 1, "revision": revision, "completed": []}, ORDER[0]
    ledger = load_object(path, "apply ledger")
    if ledger.get("schema_version") != 1 or ledger.get("revision") != revision:
        raise ValueError("apply ledger schema or revision does not match")
    completed = ledger.get("completed")
    if not isinstance(completed, list) or len(completed) >= len(ORDER):
        raise ValueError("apply ledger is malformed or already complete")
    roots = [entry.get("root") for entry in completed if isinstance(entry, dict)]
    if roots != ORDER[: len(roots)] or len(roots) != len(completed):
        raise ValueError("apply ledger is not an exact prefix of the required root order")
    for entry in completed:
        if entry.get("revision") != revision:
            raise ValueError("apply ledger entry revision does not match")
        if not SHA256.fullmatch(str(entry.get("sha256", ""))) or not SHA256.fullmatch(str(entry.get("manifest_sha256", ""))):
            raise ValueError("apply ledger entry digests are malformed")
        applied_at = entry.get("applied_at")
        if not isinstance(applied_at, str) or not applied_at.endswith("Z"):
            raise ValueError("apply ledger entry timestamp is malformed")
    return ledger, ORDER[len(completed)]


def verify_git(revision: str) -> None:
    def git(*args: str) -> str:
        result = subprocess.run(["git", "-C", str(REPOSITORY), *args], check=True, capture_output=True, text=True)
        return result.stdout.strip()

    if git("rev-parse", "HEAD") != revision or git("branch", "--show-current") != "main":
        raise ValueError("execution requires the requested revision checked out on main")
    if git("status", "--porcelain"):
        raise ValueError("execution requires a clean working tree; keep the ledger outside the repository")


def write_ledger(path: Path, ledger: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as stream:
        json.dump(ledger, stream, indent=2, sort_keys=True)
        stream.write("\n")
        temporary = Path(stream.name)
    temporary.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify and optionally apply one approved production Terraform plan.")
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--evidence", required=True, type=Path)
    parser.add_argument("--plan-file", required=True, type=Path)
    parser.add_argument("--ledger", required=True, type=Path)
    parser.add_argument("--root", required=True, choices=ORDER)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--now", help="RFC3339 clock override for deterministic verification")
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--confirmation", help="Must equal 'APPLY production-<root> <revision>' when executing")
    parser.add_argument("--terraform-executable", default="terraform")
    parser.add_argument("--terraform-arg", action="append", default=[], help="Argument inserted after the Terraform executable; intended for test wrappers")
    args = parser.parse_args()

    try:
        if not SHA.fullmatch(args.revision):
            raise ValueError("revision must be a lowercase 40-character commit SHA")
        if args.execute and args.now:
            raise ValueError("--now is test-only and cannot be used with --execute")
        manifest = load_object(args.manifest, "cutover manifest")
        evidence = load_object(args.evidence, "plan evidence")
        plan_digest = sha256(args.plan_file)

        preflight = [sys.executable, str(REPOSITORY / "scripts/production-cutover-preflight.py"), str(args.manifest), "--revision", args.revision, "--phase", "apply"]
        if args.now:
            preflight.extend(["--now", args.now])
        checked = subprocess.run(preflight, capture_output=True, text=True)
        if checked.returncode != 0:
            raise ValueError(f"cutover manifest rejected: {checked.stderr.removeprefix('FAIL: ').strip()}")

        root_name = f"production-{args.root}"
        expected = manifest.get("terraform_plans", {}).get(root_name)
        if not isinstance(expected, dict):
            raise ValueError(f"manifest does not contain {root_name} plan evidence")
        for field in ("revision", "sha256", "destructive_changes", "planned_at"):
            if evidence.get(field) != expected.get(field):
                raise ValueError(f"plan evidence {field} does not match the approved manifest")
        if evidence.get("schema_version") != 1 or evidence.get("root") != root_name:
            raise ValueError("plan evidence schema or root does not match")
        if evidence.get("revision") != args.revision or evidence.get("destructive_changes") is not False:
            raise ValueError("plan evidence revision or destructive-change decision is invalid")
        if not SHA256.fullmatch(str(evidence.get("sha256", ""))) or evidence["sha256"] != plan_digest:
            raise ValueError("decrypted plan SHA-256 does not match approved evidence")

        ledger, next_root = validate_ledger(args.ledger, args.revision)
        if args.root != next_root:
            raise ValueError(f"apply order requires production-{next_root} next")

        if not args.execute:
            print(f"PASS: production-{args.root} plan is approved, digest-matched, and next in apply order")
            return 0

        required_confirmation = f"APPLY {root_name} {args.revision}"
        if args.confirmation != required_confirmation:
            raise ValueError(f"execution confirmation must exactly equal: {required_confirmation}")
        verify_git(args.revision)
        terraform_root = REPOSITORY / "infra/aws" / root_name
        command = [args.terraform_executable, *args.terraform_arg, f"-chdir={terraform_root}", "apply", "-input=false", str(args.plan_file.resolve())]
        completed = subprocess.run(command, check=False)
        if completed.returncode != 0:
            raise ValueError(f"Terraform apply failed with exit code {completed.returncode}; ledger was not advanced")

        applied_at = args.now or datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
        ledger["completed"].append(
            {
                "root": args.root,
                "revision": args.revision,
                "sha256": plan_digest,
                "manifest_sha256": hashlib.sha256(args.manifest.read_bytes()).hexdigest(),
                "applied_at": applied_at,
            }
        )
        write_ledger(args.ledger, ledger)
        print(f"PASS: production-{args.root} applied successfully and the ledger advanced")
        return 0
    except (ValueError, subprocess.CalledProcessError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
