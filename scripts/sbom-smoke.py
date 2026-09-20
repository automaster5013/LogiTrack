import argparse
import json
import re
import uuid
from datetime import datetime
from pathlib import Path


SERVICES = ("api", "analytics", "simulator", "web", "otel-collector")
SHA_PATTERN = re.compile(r"^[0-9a-f]{40}$")


def property_map(component: dict) -> dict[str, list[str]]:
    values: dict[str, list[str]] = {}
    for item in component.get("properties", []):
        values.setdefault(item.get("name", ""), []).append(item.get("value", ""))
    return values


def validate(path: Path, service: str, tag: str, revision: str | None) -> str:
    document = json.loads(path.read_text(encoding="utf-8"))
    if document.get("bomFormat") != "CycloneDX" or document.get("specVersion") != "1.7":
        raise AssertionError(f"{path.name} is not a CycloneDX 1.7 document")
    serial = document.get("serialNumber", "")
    if not serial.startswith("urn:uuid:"):
        raise AssertionError(f"{path.name} has no UUID serial number")
    uuid.UUID(serial.removeprefix("urn:uuid:"))
    metadata = document.get("metadata", {})
    datetime.fromisoformat(metadata.get("timestamp", "").replace("Z", "+00:00"))
    component = metadata.get("component", {})
    expected_image = f"logitrack-{service}:{tag}"
    if component.get("type") != "container" or component.get("name") != expected_image:
        raise AssertionError(f"{path.name} describes {component.get('name')!r}, not {expected_image}")
    properties = property_map(component)
    if expected_image not in properties.get("aquasecurity:trivy:Reference", []):
        raise AssertionError(f"{path.name} lacks its immutable scan reference")
    image_ids = properties.get("aquasecurity:trivy:ImageID", [])
    if len(image_ids) != 1 or not re.fullmatch(r"sha256:[0-9a-f]{64}", image_ids[0]):
        raise AssertionError(f"{path.name} lacks a valid image digest")
    if revision:
        revisions = properties.get("aquasecurity:trivy:Labels:org.opencontainers.image.revision", [])
        if revisions != [revision]:
            raise AssertionError(f"{path.name} was not built from revision {revision}")
    components = document.get("components", [])
    if not components:
        raise AssertionError(f"{path.name} contains no software components")
    references = [item.get("bom-ref") for item in components]
    if any(not reference for reference in references) or len(references) != len(set(references)):
        raise AssertionError(f"{path.name} has missing or duplicate component references")
    return serial


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--revision")
    args = parser.parse_args()
    if args.revision and not SHA_PATTERN.fullmatch(args.revision):
        raise AssertionError("revision must be a full lowercase Git SHA")
    expected = {f"logitrack-{service}.cdx.json" for service in SERVICES}
    actual = {path.name for path in args.directory.glob("*.cdx.json")}
    if actual != expected:
        raise AssertionError(f"SBOM set mismatch: expected {sorted(expected)}, found {sorted(actual)}")
    serials = {
        validate(args.directory / f"logitrack-{service}.cdx.json", service, args.tag, args.revision)
        for service in SERVICES
    }
    if len(serials) != len(SERVICES):
        raise AssertionError("SBOM documents reuse a serial number")
    print(f"PASS: {len(SERVICES)} CycloneDX SBOMs match their image tags, digests, components, and source revision")


if __name__ == "__main__":
    main()
