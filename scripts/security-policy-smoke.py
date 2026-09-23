from pathlib import Path


POLICY_PATH = Path("SECURITY.md")
PRIVATE_REPORT_URL = "https://github.com/automaster5013/LogiTrack/security/advisories/new"


def main() -> None:
    policy = POLICY_PATH.read_text(encoding="utf-8")
    required = (
        "## Supported version",
        "## Reporting a vulnerability",
        "## Research guidelines",
        PRIVATE_REPORT_URL,
        "within 72 hours",
        "do not disclose suspected vulnerabilities in a public issue",
    )
    missing = [item for item in required if item.lower() not in policy.lower()]
    if missing:
        raise AssertionError(f"Security policy disclosure contract is incomplete: {missing}")
    if "mailto:" in policy.lower():
        raise AssertionError("Security reports must use the auditable private advisory channel")

    print("PASS: security policy points to the private advisory channel and defines response and research boundaries")


if __name__ == "__main__":
    main()
