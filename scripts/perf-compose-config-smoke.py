import json
import re
import subprocess


DIGEST_PATTERN = re.compile(r"@sha256:[0-9a-f]{64}$")


def main() -> None:
    result = subprocess.run(
        ["docker", "compose", "-f", "docker-compose.perf.yml", "config", "--format", "json"],
        check=True,
        capture_output=True,
        text=True,
    )
    services = json.loads(result.stdout)["services"]

    for service_name, service in services.items():
        if int(service.get("pids_limit", 0)) <= 0:
            raise AssertionError(f"{service_name} does not have a process limit")
        if int(service.get("mem_limit", 0)) <= 0:
            raise AssertionError(f"{service_name} does not have a memory limit")
        if float(service.get("cpus", 0)) <= 0:
            raise AssertionError(f"{service_name} does not have a CPU limit")
        if "no-new-privileges:true" not in service.get("security_opt", []):
            raise AssertionError(f"{service_name} can gain additional privileges")
        logging = service.get("logging", {})
        if logging.get("driver") != "json-file" or logging.get("options") != {"max-file": "2", "max-size": "10m"}:
            raise AssertionError(f"{service_name} logs are not bounded")

    for service_name in ("postgres", "redis", "kafka", "kafka-init"):
        if not DIGEST_PATTERN.search(services[service_name].get("image", "")):
            raise AssertionError(f"{service_name} uses a mutable image reference")

    for service_name in ("analytics", "api"):
        service = services[service_name]
        if service.get("read_only") is not True or "ALL" not in service.get("cap_drop", []):
            raise AssertionError(f"{service_name} does not use a read-only, capability-free runtime")
        if not any(mount.startswith("/tmp:size=") for mount in service.get("tmpfs", [])):
            raise AssertionError(f"{service_name} does not have a bounded writable /tmp")

    for port in services["api"].get("ports", []):
        if port.get("host_ip") != "127.0.0.1":
            raise AssertionError("Performance API is exposed beyond loopback")

    kafka_volumes = [
        mount for mount in services["kafka"].get("volumes", [])
        if mount.get("type") == "volume" and mount.get("target") == "/var/lib/kafka/data"
    ]
    if len(kafka_volumes) != 1 or not kafka_volumes[0].get("source", "").endswith("kafka-perf-data"):
        raise AssertionError("Kafka performance data is not isolated in an explicit volume")

    kafka_command = services["kafka-init"]["command"][-1].lstrip()
    if not kafka_command.startswith("set -eu\n"):
        raise AssertionError("Kafka performance topic initialization is not fail-fast")

    print("PASS: isolated performance Compose uses immutable images, loopback exposure, bounded resources and logs, explicit storage, and hardened runtimes")


if __name__ == "__main__":
    main()
