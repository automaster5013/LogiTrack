import re
from pathlib import Path

import yaml


WORKFLOW_PATH = Path(".github/workflows/release.yml")
PINNED_ACTION = re.compile(r"^[^@\s]+@[0-9a-f]{40}$")


def main() -> None:
    source = WORKFLOW_PATH.read_text(encoding="utf-8")
    workflow = yaml.safe_load(source)
    release = workflow["jobs"]["release"]

    if workflow.get("permissions") != "read-all":
        raise AssertionError("release workflow must default to read-only permissions")
    if release.get("permissions") != {"contents": "write", "id-token": "write"}:
        raise AssertionError("release job permissions exceed publication and keyless signing")
    if release.get("runs-on") != "ubuntu-24.04" or release.get("timeout-minutes") != 10:
        raise AssertionError("release runner or timeout is not bounded")
    if "workflow_dispatch:" not in source or "pull_request" in source or "push:" in source:
        raise AssertionError("release publication must only be manually dispatched")

    steps = release.get("steps", [])
    actions = [step["uses"] for step in steps if "uses" in step]
    if len(actions) != 2 or not all(PINNED_ACTION.fullmatch(action) for action in actions):
        raise AssertionError(f"release actions must use immutable SHAs: {actions}")
    checkout = steps[0]
    if checkout.get("with") != {"fetch-depth": 0, "persist-credentials": False}:
        raise AssertionError("release checkout must fetch history without persisted credentials")

    for boundary in (
        'test "$GITHUB_REF" = refs/heads/main',
        'test "$GITHUB_EVENT_NAME" = workflow_dispatch',
        'test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"',
        'refs/tags/$VERSION',
        "cosign-release: v3.1.3",
        "cosign sign-blob --yes --bundle",
        "cosign verify-blob",
        '--certificate-oidc-issuer "https://token.actions.githubusercontent.com"',
        'sha256sum "$archive"',
        '"/repos/$GITHUB_REPOSITORY/git/refs"',
        '--field ref="refs/tags/$VERSION"',
        '--field sha="$GITHUB_SHA"',
        'gh release create "$VERSION"',
        '--target "$GITHUB_SHA"',
        '--verify-tag',
    ):
        if boundary not in source:
            raise AssertionError(f"release trust boundary is missing: {boundary}")

    print(
        "PASS: signed GitHub releases are manual, main-bound, immutable, "
        "keyless-signed, locally verified, and SHA-256 checksummed"
    )


if __name__ == "__main__":
    main()
