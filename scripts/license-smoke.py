import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET


EXPECTED_LICENSE_SHA256 = "cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30"


def main() -> None:
    license_path = Path("LICENSE")
    if not license_path.is_file():
        raise AssertionError("root LICENSE file is missing")
    digest = hashlib.sha256(license_path.read_bytes()).hexdigest()
    if digest != EXPECTED_LICENSE_SHA256:
        raise AssertionError("LICENSE does not match the canonical Apache-2.0 text")

    package = json.loads(Path("web/package.json").read_text(encoding="utf-8"))
    if package.get("license") != "Apache-2.0":
        raise AssertionError("web/package.json must declare Apache-2.0")
    package_lock = json.loads(Path("web/package-lock.json").read_text(encoding="utf-8"))
    if package_lock.get("packages", {}).get("", {}).get("license") != "Apache-2.0":
        raise AssertionError("web/package-lock.json must declare Apache-2.0")

    namespace = {"m": "http://maven.apache.org/POM/4.0.0"}
    pom = ET.parse("api/pom.xml").getroot()
    license_node = pom.find("m:licenses/m:license", namespace)
    if license_node is None:
        raise AssertionError("api/pom.xml license metadata is missing")
    if license_node.findtext("m:name", namespaces=namespace) != "Apache License, Version 2.0":
        raise AssertionError("api/pom.xml license name is incorrect")
    if license_node.findtext("m:url", namespaces=namespace) != "https://www.apache.org/licenses/LICENSE-2.0.txt":
        raise AssertionError("api/pom.xml license URL is incorrect")

    readme = Path("README.md").read_text(encoding="utf-8")
    if "[Apache License 2.0](LICENSE)" not in readme:
        raise AssertionError("README license link is missing")

    print("PASS: canonical Apache-2.0 license and package metadata are consistent")


if __name__ == "__main__":
    main()
