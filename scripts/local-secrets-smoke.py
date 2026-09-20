import json
import os
import subprocess
import tempfile
from pathlib import Path


REQUIRED_SECRETS = ("POSTGRES_PASSWORD", "GRAFANA_ADMIN_PASSWORD")


def parse_env(path: Path) -> dict[str, str]:
    return dict(
        line.split("=", 1)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line and not line.startswith("#")
    )


def main() -> None:
    example = parse_env(Path(".env.example"))
    if any(example.get(name) for name in REQUIRED_SECRETS):
        raise AssertionError("Example environment must not publish usable credentials")
    environment = os.environ.copy()
    environment.pop("POSTGRES_PASSWORD", None)
    environment.pop("GRAFANA_ADMIN_PASSWORD", None)
    rejected = subprocess.run(
        ["docker", "compose", "--env-file", ".env.example", "config"],
        capture_output=True,
        text=True,
        env=environment,
    )
    if rejected.returncode == 0:
        raise AssertionError("Compose accepts empty required credentials")

    with tempfile.TemporaryDirectory() as directory:
        generated = Path(directory) / ".env"
        subprocess.run(
            ["pwsh", "-NoLogo", "-NoProfile", "-File", "scripts/init-env.ps1", "-OutputPath", str(generated)],
            check=True,
        )
        overwrite = subprocess.run(
            ["pwsh", "-NoLogo", "-NoProfile", "-File", "scripts/init-env.ps1", "-OutputPath", str(generated)],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        if overwrite.returncode == 0:
            raise AssertionError("Credential generator overwrote an existing environment")
        values = parse_env(generated)
        secrets = [values.get(name, "") for name in REQUIRED_SECRETS]
        if any(len(secret) < 40 for secret in secrets) or secrets[0] == secrets[1]:
            raise AssertionError("Generated credentials are missing, short, or reused")

        result = subprocess.run(
            ["docker", "compose", "--env-file", str(generated), "config", "--format", "json"],
            check=True,
            capture_output=True,
            text=True,
            env=environment,
        )
        services = json.loads(result.stdout)["services"]
        if services["postgres"]["environment"]["POSTGRES_PASSWORD"] != secrets[0]:
            raise AssertionError("Generated PostgreSQL password did not reach the database")
        if services["api"]["environment"]["DB_PASSWORD"] != secrets[0]:
            raise AssertionError("Generated PostgreSQL password did not reach the API")
        if services["grafana"]["environment"]["GF_SECURITY_ADMIN_PASSWORD"] != secrets[1]:
            raise AssertionError("Generated Grafana password did not reach Grafana")

    print("PASS: local credentials are required, independently generated, and propagated without committed defaults")


if __name__ == "__main__":
    main()
