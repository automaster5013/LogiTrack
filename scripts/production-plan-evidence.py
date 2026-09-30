#!/usr/bin/env python3
import argparse
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOTS = {"alerting", "audit", "certificates", "compute", "data", "edge"}
SHA = re.compile(r"^[0-9a-f]{40}$")


def main() -> int:
    parser = argparse.ArgumentParser(description="Create sanitized evidence for a production Terraform plan.")
    parser.add_argument("--plan-json", required=True, type=Path)
    parser.add_argument("--plan-file", required=True, type=Path)
    parser.add_argument("--root", required=True, choices=sorted(ROOTS))
    parser.add_argument("--revision", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--generated-at", help="RFC3339 timestamp override for deterministic tests")
    args = parser.parse_args()

    try:
        if not SHA.fullmatch(args.revision):
            raise ValueError("revision must be a lowercase 40-character commit SHA")
        plan = json.loads(args.plan_json.read_text(encoding="utf-8"))
        if not isinstance(plan, dict) or not plan.get("terraform_version") or not plan.get("format_version"):
            raise ValueError("terraform show output is missing version metadata")

        counts = {"create": 0, "update": 0, "read": 0, "no_op": 0}
        destructive = []
        for change in plan.get("resource_changes", []):
            actions = change.get("change", {}).get("actions", [])
            if "delete" in actions:
                destructive.append(str(change.get("address", "<unknown>")))
            for action in counts:
                if action.replace("_", "-") in actions or (action == "no_op" and "no-op" in actions):
                    counts[action] += 1
        if destructive:
            raise ValueError(f"destructive resource actions detected ({len(destructive)})")

        generated_at = args.generated_at or datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
        if not generated_at.endswith("Z"):
            raise ValueError("generated-at must be an RFC3339 UTC timestamp ending in Z")
        digest = hashlib.sha256(args.plan_file.read_bytes()).hexdigest()
        evidence = {
            "schema_version": 1,
            "root": f"production-{args.root}",
            "revision": args.revision,
            "planned_at": generated_at,
            "sha256": digest,
            "destructive_changes": False,
            "terraform_version": plan["terraform_version"],
            "plan_format_version": plan["format_version"],
            "resource_action_counts": counts,
        }
        args.output.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1

    print(f"PASS: non-destructive production-{args.root} plan evidence created for {args.revision}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
