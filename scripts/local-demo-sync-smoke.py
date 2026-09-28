from pathlib import Path


script = Path("scripts/sync-local-demo.ps1").read_text(encoding="utf-8")

build = 'docker compose up -d --build api simulator web'
cleanup = 'docker compose rm -f kafka-init'
cleanup_failure = 'throw "Local Kafka initialization container cleanup failed"'
verification = '$deadline = (Get-Date).AddSeconds(120)'

for required in (build, cleanup, cleanup_failure, verification):
    if script.count(required) != 1:
        raise AssertionError(f"local demo sync must contain exactly one {required!r}")

if not script.index(build) < script.index(cleanup) < script.index(verification):
    raise AssertionError(
        "one-shot Kafka cleanup must run after Compose start and before live fleet verification"
    )

cleanup_block = script[script.index(cleanup) : script.index(verification)]
if "$LASTEXITCODE -ne 0" not in cleanup_block or cleanup_failure not in cleanup_block:
    raise AssertionError("one-shot Kafka cleanup failures must fail the local sync")

if "docker container prune" in script or "docker system prune" in script:
    raise AssertionError("local sync must only remove its named one-shot dependency")

print("local demo sync cleanup contract smoke passed")
