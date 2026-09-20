import json
import os
import re
import subprocess
from pathlib import Path


DIGEST_PATTERN = re.compile(r"@sha256:[0-9a-f]{64}$")


def rendered_compose() -> dict:
    environment = os.environ.copy()
    environment.update(
        POSTGRES_DB="logitrack_override_db",
        POSTGRES_USER="logitrack_override_user",
        POSTGRES_PASSWORD="logitrack_override_password",
    )
    result = subprocess.run(
        ["docker", "compose", "--profile", "scale-test", "config", "--format", "json"],
        check=True,
        capture_output=True,
        text=True,
        env=environment,
    )
    return json.loads(result.stdout)


def main() -> None:
    services = rendered_compose()["services"]
    expected_database = {
        "DB_URL": "jdbc:postgresql://postgres:5432/logitrack_override_db",
        "DB_USER": "logitrack_override_user",
        "DB_PASSWORD": "logitrack_override_password",
    }
    for service_name in ("api", "api-replica"):
        environment = services[service_name]["environment"]
        for key, value in expected_database.items():
            if environment.get(key) != value:
                raise AssertionError(f"{service_name} does not inherit {key}")

    postgres_healthcheck = " ".join(services["postgres"]["healthcheck"]["test"])
    for variable in ("POSTGRES_USER", "POSTGRES_DB"):
        if variable not in postgres_healthcheck:
            raise AssertionError(f"PostgreSQL healthcheck does not use {variable}")

    kafka_command = services["kafka-init"]["command"][-1].lstrip()
    if not kafka_command.startswith("set -eu\n"):
        raise AssertionError("Kafka topic initialization is not fail-fast")

    long_running_services = {
        "postgres", "redis", "kafka", "analytics", "api", "api-replica",
        "simulator", "web", "tempo", "otel-collector", "prometheus", "grafana",
    }
    for service_name in long_running_services:
        if services[service_name].get("restart") != "unless-stopped":
            raise AssertionError(f"{service_name} does not automatically recover after a runtime restart")
    if services["kafka-init"].get("restart"):
        raise AssertionError("One-shot kafka-init must not have a restart policy")

    for service_name, service in services.items():
        logging = service.get("logging", {})
        options = logging.get("options", {})
        if logging.get("driver") != "json-file":
            raise AssertionError(f"{service_name} does not use the bounded json-file log driver")
        if options.get("max-size") != "10m" or options.get("max-file") != "3":
            raise AssertionError(f"{service_name} does not enforce the shared log rotation limits")

    for service_name in long_running_services:
        if not services[service_name].get("healthcheck", {}).get("test"):
            raise AssertionError(f"{service_name} does not expose runtime readiness")
    if "SIMULATOR_HEALTH_FILE" not in services["simulator"]["environment"]:
        raise AssertionError("simulator heartbeat path is not configured")
    if services["web"]["environment"].get("HOSTNAME") != "0.0.0.0":
        raise AssertionError("web is not bound to every container interface")

    for service_name, service in services.items():
        for port in service.get("ports", []):
            if port.get("host_ip") != "127.0.0.1":
                published = port.get("published", "unknown")
                raise AssertionError(
                    f"{service_name} published port {published} is not restricted to loopback"
                )

    readiness_dependencies = {
        "otel-collector": ("tempo",),
        "prometheus": ("api",),
        "grafana": ("prometheus", "tempo"),
    }
    for service_name, dependencies in readiness_dependencies.items():
        for dependency in dependencies:
            condition = services[service_name]["depends_on"][dependency]["condition"]
            if condition != "service_healthy":
                raise AssertionError(f"{service_name} does not wait for healthy {dependency}")

    external_images = ("postgres", "redis", "kafka", "kafka-init", "tempo", "prometheus", "grafana")
    for service_name in external_images:
        image = services[service_name].get("image", "")
        if not DIGEST_PATTERN.search(image):
            raise AssertionError(f"{service_name} image is not pinned by digest")

    dockerfiles = (
        Path("api/Dockerfile"),
        Path("analytics/Dockerfile"),
        Path("simulator/Dockerfile"),
        Path("web/Dockerfile"),
        Path("infra/otel/Dockerfile"),
    )
    for dockerfile in dockerfiles:
        for line in dockerfile.read_text(encoding="utf-8").splitlines():
            if line.startswith("FROM "):
                image = line.split()[1]
                if not DIGEST_PATTERN.search(image):
                    raise AssertionError(f"{dockerfile} base image is not pinned by digest: {image}")

    print("PASS: topology, loopback ports, bounded logs, runtime readiness, restart policies, and immutable image sources are valid")


if __name__ == "__main__":
    main()
