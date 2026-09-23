import re
from pathlib import Path


LOCK_PAIRS = (
    (Path("analytics/requirements.in"), Path("analytics/requirements.txt")),
    (Path("simulator/requirements.in"), Path("simulator/requirements.txt")),
    (Path("scripts/requirements.in"), Path("scripts/requirements.txt")),
)
LOCK_ENTRY = re.compile(r"^([A-Za-z0-9_.-]+)==([^\s\\]+)")


def direct_requirements(path: Path) -> dict[str, str]:
    result = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith(("#", "-r ")):
            continue
        match = LOCK_ENTRY.match(line)
        if not match:
            raise AssertionError(f"{path} has an unpinned direct requirement: {line}")
        result[match.group(1).lower().replace("_", "-")] = match.group(2)
    return result


def locked_requirements(path: Path) -> dict[str, tuple[str, bool]]:
    lines = path.read_text(encoding="utf-8").splitlines()
    result: dict[str, tuple[str, bool]] = {}
    for index, line in enumerate(lines):
        match = LOCK_ENTRY.match(line)
        if not match:
            continue
        next_entry = next(
            (candidate for candidate in range(index + 1, len(lines)) if LOCK_ENTRY.match(lines[candidate])),
            len(lines),
        )
        block = "\n".join(lines[index:next_entry])
        result[match.group(1).lower().replace("_", "-")] = (
            match.group(2),
            "--hash=sha256:" in block,
        )
    if not result or not all(has_hash for _, has_hash in result.values()):
        raise AssertionError(f"{path} contains an unhashed dependency")
    return result


def main() -> None:
    for source, lock in LOCK_PAIRS:
        direct = direct_requirements(source)
        locked = locked_requirements(lock)
        for name, version in direct.items():
            if locked.get(name) != (version, True):
                raise AssertionError(f"{lock} does not preserve {name}=={version} with hashes")

    ci_lock = locked_requirements(Path("scripts/requirements-ci.txt"))
    if ci_lock.get("pytest") != ("9.1.1", True):
        raise AssertionError("CI pytest dependency is not version-and-hash locked")

    ci = Path(".github/workflows/ci.yml").read_text(encoding="utf-8")
    analytics_dockerfile = Path("analytics/Dockerfile").read_text(encoding="utf-8")
    simulator_dockerfile = Path("simulator/Dockerfile").read_text(encoding="utf-8")
    if "--require-hashes -r scripts/requirements-ci.txt" not in ci:
        raise AssertionError("CI does not enforce the combined Python hash lock")
    for path, source in (("analytics/Dockerfile", analytics_dockerfile), ("simulator/Dockerfile", simulator_dockerfile)):
        if "pip install --no-cache-dir --require-hashes -r requirements.txt" not in source:
            raise AssertionError(f"{path} does not enforce package hashes")

    compiler = Path("scripts/compile-python-locks.ps1").read_text(encoding="utf-8")
    for boundary in (
        "ghcr.io/astral-sh/uv@sha256:",
        "--python-version 3.12",
        "--universal",
        "--generate-hashes",
        '"logitrack-uv-cache:/root/.cache/uv"',
    ):
        if boundary not in compiler:
            raise AssertionError(f"Python lock compiler is missing boundary: {boundary}")

    print("PASS: Python runtime and CI dependencies are transitively pinned and SHA-256 verified")


if __name__ == "__main__":
    main()
