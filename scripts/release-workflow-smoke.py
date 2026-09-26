import re
from pathlib import Path

import yaml


WORKFLOW_PATH = Path(".github/workflows/release.yml")
BACKFILL_WORKFLOW_PATH = Path(".github/workflows/release-provenance.yml")
PINNED_ACTION = re.compile(r"^[^@\s]+@[0-9a-f]{40}$")
SLSA_GENERATOR = (
    "slsa-framework/slsa-github-generator/.github/workflows/"
    "generator_generic_slsa3.yml@f7dd8c54c2067bafc12ca7a55595d5ee9b75204a"
)


def main() -> None:
    source = WORKFLOW_PATH.read_text(encoding="utf-8")
    backfill_source = BACKFILL_WORKFLOW_PATH.read_text(encoding="utf-8")
    workflow = yaml.safe_load(source)
    backfill = yaml.safe_load(backfill_source)
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

    provenance = workflow["jobs"].get("provenance", {})
    if provenance.get("uses") != SLSA_GENERATOR:
        raise AssertionError("release provenance must pin the trusted builder release commit")
    if provenance.get("permissions") != {
        "actions": "read",
        "contents": "write",
        "id-token": "write",
    }:
        raise AssertionError("release provenance permissions exceed generation and upload")
    provenance_inputs = provenance.get("with", {})
    if provenance_inputs.get("upload-assets") is not True or not str(
        provenance_inputs.get("provenance-name", "")
    ).endswith(".intoto.jsonl"):
        raise AssertionError("release provenance is not attached as an in-toto release asset")

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
        'echo "hashes=$(sha256sum "$archive" | base64 -w0)"',
        '"/repos/$GITHUB_REPOSITORY/git/refs"',
        '--field ref="refs/tags/$VERSION"',
        '--field sha="$GITHUB_SHA"',
        'gh release create "$VERSION"',
        '--target "$GITHUB_SHA"',
        '--verify-tag',
    ):
        if boundary not in source:
            raise AssertionError(f"release trust boundary is missing: {boundary}")

    if backfill.get("permissions") != "read-all":
        raise AssertionError("provenance backfill must default to read-only permissions")
    prepare = backfill["jobs"].get("prepare", {})
    if prepare.get("permissions") is not None:
        raise AssertionError("provenance backfill preparation must not elevate permissions")
    backfill_steps = prepare.get("steps", [])
    backfill_actions = [step["uses"] for step in backfill_steps if "uses" in step]
    if len(backfill_actions) != 1 or not PINNED_ACTION.fullmatch(backfill_actions[0]):
        raise AssertionError("provenance backfill preparation action must use an immutable SHA")
    backfill_provenance = backfill["jobs"].get("provenance", {})
    if backfill_provenance.get("uses") != SLSA_GENERATOR:
        raise AssertionError("provenance backfill must use the trusted SLSA generator")
    if backfill_provenance.get("permissions") != {
        "actions": "read",
        "contents": "write",
        "id-token": "write",
    }:
        raise AssertionError("provenance backfill permissions exceed generation and upload")
    for boundary in (
        'test "$GITHUB_REF" = refs/heads/main',
        'test "$GITHUB_EVENT_NAME" = workflow_dispatch',
        'test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"',
        'git merge-base --is-ancestor "$tag_commit" origin/main',
        "--jq 'all(.[]; . == false)'",
        'sha256sum --check --strict "$checksum"',
        'cmp --silent expected.tar.gz "$archive"',
        '.tar.gz.intoto.jsonl',
    ):
        if boundary not in backfill_source:
            raise AssertionError(f"provenance backfill boundary is missing: {boundary}")

    print(
        "PASS: signed GitHub releases are manual, main-bound, immutable, "
        "keyless-signed, locally verified, SHA-256 checksummed, and SLSA-attested"
    )


if __name__ == "__main__":
    main()
