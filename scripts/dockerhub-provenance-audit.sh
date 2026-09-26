#!/usr/bin/env bash
set -euo pipefail

revision="${1:?usage: dockerhub-provenance-audit.sh <full-main-revision>}"
repository="${GITHUB_REPOSITORY:-automaster5013/LogiTrack}"
namespace="automaster5013"

[[ "$revision" =~ ^[0-9a-f]{40}$ ]]
test "$repository" = "automaster5013/LogiTrack"
command -v curl >/dev/null
command -v gh >/dev/null
command -v jq >/dev/null

mkdir -p work/dockerhub-provenance-audit
for service in api analytics simulator web otel-collector; do
  tag_url="https://hub.docker.com/v2/repositories/$namespace/logitrack-$service/tags/$revision"
  tag_file="work/dockerhub-provenance-audit/logitrack-$service.tag.json"
  report="work/dockerhub-provenance-audit/logitrack-$service.provenance.json"
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    --retry 3 --retry-all-errors --connect-timeout 10 --max-time 60 \
    --output "$tag_file" "$tag_url"
  digest="$(jq -er --arg revision "$revision" '
    select(.name == $revision) | .digest |
    select(test("^sha256:[0-9a-f]{64}$"))
  ' "$tag_file")"
  jq -e '
    [.images[] | select(.os == "linux" and .architecture == "amd64")] | length == 1
  ' "$tag_file" >/dev/null

  subject="docker.io/$namespace/logitrack-$service"
  gh attestation verify "oci://$subject@$digest" \
    --repo "$repository" \
    --signer-workflow "$repository/.github/workflows/publish-dockerhub-images.yml" \
    --source-ref refs/heads/main \
    --source-digest "$revision" \
    --deny-self-hosted-runners \
    --bundle-from-oci \
    --format json > "$report"
  jq -e --arg name "$subject" --arg digest "${digest#sha256:}" '
    type == "array" and length >= 1 and
    any(.[].verificationResult.statement;
      .predicateType == "https://slsa.dev/provenance/v1" and
      any(.subject[]; .name == $name and .digest.sha256 == $digest))
  ' "$report" >/dev/null
done

echo "PASS: current main Docker Hub image provenance is present and cryptographically valid"
