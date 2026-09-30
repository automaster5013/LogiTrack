#!/usr/bin/env python3
import argparse
import json
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlparse

ROOTS = {
    "production-state",
    "production-alerting",
    "production-audit",
    "production-certificates",
    "production-data",
    "production-compute",
    "production-edge",
}
DRILLS = {"backup_restore", "regional_failover", "load", "rollback"}
APPROVAL_ROLES = {"business", "security", "operations"}
SHA = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")


def timestamp(value: object, field: str) -> datetime:
    if not isinstance(value, str):
        raise ValueError(f"{field} must be an RFC3339 timestamp")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError(f"{field} must be an RFC3339 timestamp") from exc
    if parsed.tzinfo is None:
        raise ValueError(f"{field} must include a timezone")
    return parsed.astimezone(timezone.utc)


def https_url(value: object, field: str) -> None:
    parsed = urlparse(value if isinstance(value, str) else "")
    if parsed.scheme != "https" or not parsed.netloc or parsed.username or parsed.password:
        raise ValueError(f"{field} must be an HTTPS URL without embedded credentials")


def validate(manifest: dict, revision: str, now: datetime, phase: str = "prepare") -> None:
    if manifest.get("schema_version") != 1:
        raise ValueError("schema_version must be 1")
    if not SHA.fullmatch(revision) or manifest.get("revision") != revision:
        raise ValueError("manifest revision must equal the requested full commit SHA")
    https_url(manifest.get("change_ticket_url"), "change_ticket_url")

    approvals = manifest.get("approvals")
    if not isinstance(approvals, list) or len(approvals) < 3:
        raise ValueError("at least three approvals are required")
    roles = {item.get("role") for item in approvals if isinstance(item, dict)}
    actors = {item.get("actor") for item in approvals if isinstance(item, dict)}
    if roles != APPROVAL_ROLES or None in actors or len(actors) < 3:
        raise ValueError("distinct business, security, and operations approvals are required")
    for index, approval in enumerate(approvals):
        approved_at = timestamp(approval.get("approved_at"), f"approvals[{index}].approved_at")
        if approved_at > now or now - approved_at > timedelta(days=7):
            raise ValueError("approvals must be no older than seven days and not in the future")

    window = manifest.get("window", {})
    start = timestamp(window.get("start"), "window.start")
    end = timestamp(window.get("end"), "window.end")
    if end <= start or end - start > timedelta(hours=4):
        raise ValueError("cutover window must last no more than four hours")
    if phase == "prepare" and (start < now or start > now + timedelta(days=30)):
        raise ValueError("cutover window must start within 30 days")
    if phase == "apply" and not start <= now <= end:
        raise ValueError("current time must be inside the approved cutover window")

    plans = manifest.get("terraform_plans")
    if not isinstance(plans, dict) or set(plans) != ROOTS:
        raise ValueError(f"terraform_plans must contain exactly: {', '.join(sorted(ROOTS))}")
    for root, plan in plans.items():
        if plan.get("revision") != revision or not SHA256.fullmatch(str(plan.get("sha256", ""))):
            raise ValueError(f"{root} plan must be bound to the revision and have a SHA-256 digest")
        if plan.get("destructive_changes") is not False:
            raise ValueError(f"{root} plan contains or does not explicitly exclude destructive changes")
        planned_at = timestamp(plan.get("planned_at"), f"{root}.planned_at")
        if planned_at > now or now - planned_at > timedelta(hours=24):
            raise ValueError(f"{root} plan must be generated within 24 hours")

    readiness = manifest.get("readiness", {})
    expected = {
        "regional_paging_subscription": "confirmed",
        "global_paging_subscription": "confirmed",
        "origin_certificate": "issued",
        "viewer_certificate": "issued",
    }
    for field, state in expected.items():
        if readiness.get(field) != state:
            raise ValueError(f"readiness.{field} must be {state}")
    ttl = readiness.get("dns_ttl_seconds")
    if not isinstance(ttl, int) or isinstance(ttl, bool) or ttl < 30 or ttl > 300:
        raise ValueError("readiness.dns_ttl_seconds must be between 30 and 300")

    drills = manifest.get("drills")
    if not isinstance(drills, dict) or set(drills) != DRILLS:
        raise ValueError(f"drills must contain exactly: {', '.join(sorted(DRILLS))}")
    for name, drill in drills.items():
        if drill.get("status") != "passed":
            raise ValueError(f"{name} drill has not passed")
        completed_at = timestamp(drill.get("completed_at"), f"{name}.completed_at")
        if completed_at > now or now - completed_at > timedelta(days=30):
            raise ValueError(f"{name} drill must have passed within 30 days")
        https_url(drill.get("evidence_url"), f"{name}.evidence_url")

    rollback = manifest.get("rollback", {})
    tested_at = timestamp(rollback.get("tested_at"), "rollback.tested_at")
    deadline = rollback.get("deadline_minutes")
    triggers = rollback.get("triggers")
    if not rollback.get("owner") or not isinstance(deadline, int) or isinstance(deadline, bool) or not 1 <= deadline <= 30:
        raise ValueError("rollback owner and a deadline of 1..30 minutes are required")
    if not isinstance(triggers, list) or len(triggers) < 2 or any(not str(item).strip() for item in triggers):
        raise ValueError("at least two explicit rollback triggers are required")
    if tested_at > now or now - tested_at > timedelta(days=30):
        raise ValueError("rollback procedure must have been tested within 30 days")


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate production cutover evidence.")
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--now", help="RFC3339 clock override for deterministic verification")
    parser.add_argument("--phase", choices=("prepare", "apply"), default="prepare")
    args = parser.parse_args()
    try:
        payload = json.loads(args.manifest.read_text(encoding="utf-8"))
        if not isinstance(payload, dict):
            raise ValueError("manifest root must be an object")
        now = timestamp(args.now, "--now") if args.now else datetime.now(timezone.utc)
        validate(payload, args.revision, now, args.phase)
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    print(f"PASS: production cutover evidence is complete for {args.revision}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
