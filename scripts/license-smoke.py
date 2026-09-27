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

    documentation_start = readme.index("## 문서")
    license_start = readme.index("## 라이선스")
    validation_start = readme.index("## 로컬 검증")
    if not documentation_start < license_start < validation_start:
        raise AssertionError("README documentation, license, and validation sections are out of order")

    documentation = readme[documentation_start:license_start]
    license_section = readme[license_start:validation_start]
    documentation_links = (
        "[테스트 품질 기준선](docs/quality.md)",
        "[CI/CD와 릴리스 전략](docs/delivery.md)",
        "[10분 데모 시나리오](docs/demo.md)",
        "[구현 진행 현황](docs/progress.md)",
        "[기여 가이드](CONTRIBUTING.md)",
        "[행동강령](CODE_OF_CONDUCT.md)",
    )
    missing_documentation = [link for link in documentation_links if link not in documentation]
    if missing_documentation:
        raise AssertionError(f"README documentation navigation is incomplete: {missing_documentation}")
    if any(link in license_section for link in documentation_links):
        raise AssertionError("README documentation links must not be rendered inside the license section")

    print("PASS: canonical Apache-2.0 license, package metadata, and README navigation are consistent")


if __name__ == "__main__":
    main()
