from pathlib import Path

import yaml


workflow_path = Path(".github/workflows/dockerhub-provenance-audit.yml")
source = workflow_path.read_text(encoding="utf-8")
workflow = yaml.safe_load(source)
trigger = workflow.get(True, workflow.get("on", {}))
job = workflow.get("jobs", {}).get("audit", {})
errors = []

if set(trigger) != {"workflow_dispatch", "schedule"}:
    errors.append("audit triggers drifted")
if trigger.get("schedule") != [{"cron": "41 19 * * *"}]:
    errors.append("audit cadence drifted")
if workflow.get("permissions") != {"contents": "read", "attestations": "read"}:
    errors.append("audit token permissions drifted")
if "environment" in job or "secrets" in source:
    errors.append("public provenance audit must not receive deployment secrets")
if job.get("runs-on") != "ubuntu-24.04" or job.get("timeout-minutes") != 10:
    errors.append("audit runner bounds drifted")

required = (
    "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1",
    "ref: main",
    "persist-credentials: false",
    "GH_CLI_VERSION: 2.101.0",
    "GH_CLI_ARCHIVE_SHA256: 9bca2d1c16825f109907a23307628a2f0698fbf99662b73a5cf0b020293072b8",
    "ARTIFACT_RETENTION_DAYS: 30",
    "sha256sum --check --strict",
    'test "$revision" = "$(git rev-parse origin/main)"',
    './scripts/dockerhub-provenance-audit.sh "$revision"',
    "Seal provenance audit evidence",
    'test "$(find . -maxdepth 1 -type f -name \'*.json\' | wc -l)" -eq 10',
    "sha256sum --check --strict SHA256SUMS",
    "actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a",
    "dockerhub-provenance-audit-${{ github.sha }}-${{ github.run_attempt }}",
    "retention-days: ${{ env.ARTIFACT_RETENTION_DAYS }}",
    "EVIDENCE_DIGEST: sha256:${{ steps.evidence.outputs.artifact-digest }}",
    "EVIDENCE_URL: ${{ steps.evidence.outputs.artifact-url }}",
)
for boundary in required:
    if boundary not in source:
        errors.append(f"audit workflow is missing boundary: {boundary}")

script = Path("scripts/dockerhub-provenance-audit.sh").read_text(encoding="utf-8")
script_boundaries = (
    "automaster5013/LogiTrack",
    "https://hub.docker.com/v2/repositories/",
    "api analytics simulator web otel-collector",
    "gh attestation verify",
    "--signer-workflow",
    "--source-ref refs/heads/main",
    '--source-digest "$revision"',
    "--deny-self-hosted-runners",
    "--bundle-from-oci",
    'https://slsa.dev/provenance/v1',
)
for boundary in script_boundaries:
    if boundary not in script:
        errors.append(f"audit script is missing boundary: {boundary}")

if errors:
    raise SystemExit("\n".join(f"ERROR: {error}" for error in errors))
print("PASS: scheduled Docker Hub provenance audit is secretless, pinned, main-bound, and cryptographic")
