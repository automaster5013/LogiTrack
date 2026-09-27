import json
import re
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


def validation_block(document: str, marker: str, language: str) -> tuple[str, ...]:
    if document.count(marker) != 1:
        raise AssertionError(f"validation section marker must occur exactly once: {marker}")
    marker_index = document.index(marker)
    section_start = marker_index + len(marker)
    section_end = document.find("\n## ", section_start)
    section = document[section_start : section_end if section_end >= 0 else len(document)]
    block = re.match(
        rf"\A[\t \r\n]*```{re.escape(language)}\r?\n(?P<body>.*?)\r?\n```",
        section,
        flags=re.DOTALL,
    )
    if block is None:
        raise AssertionError(f"validation section must start with a {language} code block: {marker}")
    return tuple(line.strip() for line in block.group("body").splitlines() if line.strip())


def main() -> None:
    guide = CONTRIBUTING_PATH.read_text(encoding="utf-8")
    readme = README_PATH.read_text(encoding="utf-8")
    package = json.loads(PACKAGE_PATH.read_text(encoding="utf-8"))
    scripts = package.get("scripts", {})

    guide_commands = validation_block(
        guide,
        "Run the checks relevant to your change before opening a pull request:",
        "powershell",
    )
    readme_commands = validation_block(readme, "## 로컬 검증", "bash")
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
