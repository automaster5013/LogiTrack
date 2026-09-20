from pathlib import Path

import yaml


EXPECTED_LOCATIONS = {
    "github-actions": {"/"},
    "maven": {"/api"},
    "npm": {"/web"},
    "pip": {"/analytics", "/simulator", "/scripts"},
    "docker": {"/api", "/analytics", "/simulator", "/web", "/infra/otel"},
    "docker-compose": {"/"},
}


def main() -> None:
    config = yaml.safe_load(Path(".github/dependabot.yml").read_text(encoding="utf-8"))
    if config.get("version") != 2:
        raise AssertionError("Dependabot config version must be 2")

    updates = config.get("updates", [])
    configured = {}
    for update in updates:
        ecosystem = update["package-ecosystem"]
        locations = set(update.get("directories", [update.get("directory")]))
        configured[ecosystem] = locations
        schedule = update.get("schedule", {})
        if schedule.get("interval") != "weekly" or schedule.get("timezone") != "Asia/Seoul":
            raise AssertionError(f"{ecosystem} does not use the weekly Asia/Seoul schedule")
        if update.get("open-pull-requests-limit", 0) < 1:
            raise AssertionError(f"{ecosystem} disables version update pull requests")

    if configured != EXPECTED_LOCATIONS:
        raise AssertionError(f"Dependabot coverage mismatch: {configured}")

    print("PASS: Dependabot covers actions, application dependencies, and all container sources")


if __name__ == "__main__":
    main()
