from pathlib import Path


REQUIRED_RULES = {
    "api": {"target/", ".env*", "*.log"},
    "analytics": {"__pycache__/", "*.py[cod]", ".pytest_cache/", "tests/", ".env*", "*.log"},
    "simulator": {"__pycache__/", "*.py[cod]", ".pytest_cache/", "tests/", ".env*", "*.log"},
    "web": {"node_modules/", ".next/", ".env*", "coverage/", "*.log"},
    "infra/otel": {"*", "!Dockerfile"},
}


def rules_for(context: str) -> set[str]:
    path = Path(context) / ".dockerignore"
    if not path.is_file():
        raise AssertionError(f"{context} has no .dockerignore")
    return {
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    }


def main() -> None:
    for context, required in REQUIRED_RULES.items():
        missing = required - rules_for(context)
        if missing:
            raise AssertionError(f"{context} .dockerignore is missing: {sorted(missing)}")

    web_dockerfile = Path("web/Dockerfile").read_text(encoding="utf-8")
    if "COPY . ." in web_dockerfile and ".env*" not in rules_for("web"):
        raise AssertionError("web broad COPY can include local environment files")

    print("PASS: all production image contexts exclude secrets, caches, and test artifacts")


if __name__ == "__main__":
    main()
