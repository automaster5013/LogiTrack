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


def validation_block(document: str, marker: str) -> tuple[str, ...]:
    marker_index = document.find(marker)
    if marker_index < 0:
        raise AssertionError(f"validation section marker is missing: {marker}")

    fence_start = document.find("```", marker_index + len(marker))
    if fence_start < 0:
        raise AssertionError(f"validation code block is missing after: {marker}")
    content_start = document.find("\n", fence_start)
    fence_end = document.find("```", content_start + 1)
    if content_start < 0 or fence_end < 0:
        raise AssertionError(f"validation code block is not closed after: {marker}")

    return tuple(line.strip() for line in document[content_start + 1 : fence_end].splitlines() if line.strip())


def main() -> None:
    guide = CONTRIBUTING_PATH.read_text(encoding="utf-8")
    readme = README_PATH.read_text(encoding="utf-8")
    package = json.loads(PACKAGE_PATH.read_text(encoding="utf-8"))
    scripts = package.get("scripts", {})

    guide_commands = validation_block(guide, "Run the checks relevant to your change before opening a pull request:")
    readme_commands = validation_block(readme, "## 로컬 검증")
    if guide_commands != VALIDATION_COMMANDS:
        raise AssertionError("contributor validation block must contain the ordered core commands only")
    if readme_commands != VALIDATION_COMMANDS:
        raise AssertionError("README local validation block must contain the ordered core commands only")
    if "npm test" in guide or "npm run test" in guide:
        raise AssertionError("contributor guide references a web test script that does not exist")
    if "build" not in scripts:
        raise AssertionError("web/package.json must define the documented build script")

    print("PASS: contributor validation commands match the available web scripts and CI build")


if __name__ == "__main__":
    main()
