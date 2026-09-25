from pathlib import Path


migrations = "\n".join(
    path.read_text(encoding="utf-8")
    for path in Path("api/src/main/resources/db/migration").glob("V*.sql")
)
runtime_smoke = Path("scripts/data-integrity-smoke.ps1").read_text(encoding="utf-8")

required = (
    "dead_letter_status_values",
    "dead_letter_terminal_state",
    "replay_audit_action_values",
    "replay_audit_reason_state",
)
missing_migrations = [name for name in required if f"CONSTRAINT {name}" not in migrations]
missing_runtime = [name for name in required if f'"{name}"' not in runtime_smoke]
if missing_migrations or missing_runtime:
    raise SystemExit(
        "ERROR: DLQ integrity contract drifted; missing migration constraints "
        + ", ".join(missing_migrations)
        + "; missing runtime expectations "
        + ", ".join(missing_runtime)
    )
if '"dead_letter_replay_state"' in runtime_smoke:
    raise SystemExit("ERROR: runtime integrity smoke still expects the pre-discard DLQ constraint")

print("PASS: runtime DB integrity smoke tracks replay, discard, and replay-audit migration constraints")
