import json
from pathlib import Path


CONTRIBUTING_PATH = Path("CONTRIBUTING.md")
PACKAGE_PATH = Path("web/package.json")
WEB_VALIDATION_COMMAND = "Push-Location web; npm ci; npm run build; Pop-Location"


def main() -> None:
    guide = CONTRIBUTING_PATH.read_text(encoding="utf-8")
    package = json.loads(PACKAGE_PATH.read_text(encoding="utf-8"))
    scripts = package.get("scripts", {})

    if WEB_VALIDATION_COMMAND not in guide:
        raise AssertionError("contributor web validation must match the locked CI build")
    if "npm test" in guide or "npm run test" in guide:
        raise AssertionError("contributor guide references a web test script that does not exist")
    if "build" not in scripts:
        raise AssertionError("web/package.json must define the documented build script")

    print("PASS: contributor validation commands match the available web scripts and CI build")


if __name__ == "__main__":
    main()
