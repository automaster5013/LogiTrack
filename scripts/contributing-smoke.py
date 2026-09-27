import json
from pathlib import Path


CONTRIBUTING_PATH = Path("CONTRIBUTING.md")
README_PATH = Path("README.md")
PACKAGE_PATH = Path("web/package.json")
VALIDATION_COMMANDS = (
    "python -m unittest discover simulator/tests",
    "python -m unittest discover analytics/tests",
    "python scripts/compose-config-smoke.py",
    "python scripts/markdown-link-smoke.py",
    "pwsh ./scripts/domain-coverage.ps1",
    "Push-Location web; npm ci; npm run build; Pop-Location",
)


def main() -> None:
    guide = CONTRIBUTING_PATH.read_text(encoding="utf-8")
    readme = README_PATH.read_text(encoding="utf-8")
    package = json.loads(PACKAGE_PATH.read_text(encoding="utf-8"))
    scripts = package.get("scripts", {})

    for command in VALIDATION_COMMANDS:
        if command not in guide:
            raise AssertionError(f"contributor guide must include the core validation command: {command}")
        if command not in readme:
            raise AssertionError(f"README local validation must include the core validation command: {command}")
    if "npm test" in guide or "npm run test" in guide:
        raise AssertionError("contributor guide references a web test script that does not exist")
    if "build" not in scripts:
        raise AssertionError("web/package.json must define the documented build script")

    print("PASS: contributor validation commands match the available web scripts and CI build")


if __name__ == "__main__":
    main()
