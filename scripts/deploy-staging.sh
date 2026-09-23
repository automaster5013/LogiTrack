#!/usr/bin/env bash
set -euo pipefail

revision="${1:?usage: deploy-staging.sh <40-char revision> <release-manifest.json>}"
manifest="${2:?release manifest path is required}"
region="${AWS_REGION:-ap-northeast-2}"
account_id="${AWS_ACCOUNT_ID:?AWS_ACCOUNT_ID is required}"
source_dir="$(cd "$(dirname "$0")/../deploy/staging" && pwd)"
root=/opt/logitrack
release="$root/releases/$revision"
previous=""

[[ "$revision" =~ ^[0-9a-f]{40}$ ]] || { echo "revision must be a full lowercase SHA" >&2; exit 2; }
[[ "$account_id" =~ ^[0-9]{12}$ ]] || { echo "AWS_ACCOUNT_ID must be a 12-digit account" >&2; exit 2; }
jq -e --arg revision "$revision" --arg account "$account_id" --arg region "$region" '
  .schemaVersion == 20 and .revision == $revision and .awsAccountId == $account and
  .awsRegion == $region and .deploymentEnvironment == "staging" and
  .imagePlatform == "linux/amd64" and (.images | length == 5) and
  ([.images[].service] | sort == ["analytics","api","otel-collector","simulator","web"]) and
  all(.images[]; (.digest | test("^sha256:[0-9a-f]{64}$")) and
    (.uri == ($account + ".dkr.ecr." + $region + ".amazonaws.com/" + .repository + "@" + .digest)))
' "$manifest" >/dev/null

if [[ -L "$root/current" ]]; then previous="$(readlink -f "$root/current")"; fi
rm -rf "$release"
install -d -m 0700 "$release"
install -m 0644 "$source_dir/compose.yml" "$release/compose.yml"
install -m 0644 "$source_dir/Caddyfile" "$release/Caddyfile"
install -m 0600 "$manifest" "$release/release-manifest.json"

parameter() {
  aws ssm get-parameter --region "$region" --name "$1" --with-decryption --query Parameter.Value --output text
}
postgres_password="$(parameter /logitrack/staging/postgres-password)"
auth_base="$(parameter /logitrack/staging/cognito-authorization-base-url)"
issuer="$(parameter /logitrack/staging/cognito-issuer-uri)"
client_id="$(parameter /logitrack/staging/cognito-client-id)"
[[ -n "$postgres_password" && -n "$auth_base" && -n "$issuer" && -n "$client_id" ]] || { echo "a runtime parameter is empty" >&2; exit 3; }
[[ "$postgres_password" =~ ^[A-Za-z0-9]{32,128}$ ]] || { echo "postgres password must be 32-128 alphanumeric characters for safe Compose injection" >&2; exit 3; }

image_uri() { jq -er --arg service "$1" '.images[] | select(.service == $service) | .uri' "$manifest"; }
{
  printf 'API_IMAGE=%s\n' "$(image_uri api)"
  printf 'ANALYTICS_IMAGE=%s\n' "$(image_uri analytics)"
  printf 'SIMULATOR_IMAGE=%s\n' "$(image_uri simulator)"
  printf 'WEB_IMAGE=%s\n' "$(image_uri web)"
  printf 'POSTGRES_PASSWORD=%s\n' "$postgres_password"
  printf 'COGNITO_AUTHORIZATION_BASE_URL=%s\n' "$auth_base"
  printf 'COGNITO_ISSUER_URI=%s\n' "$issuer"
  printf 'COGNITO_CLIENT_ID=%s\n' "$client_id"
} >"$release/.env"
chmod 0600 "$release/.env"
unset postgres_password auth_base issuer client_id

registry="$account_id.dkr.ecr.$region.amazonaws.com"
aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$registry"
docker compose --project-directory "$release" --env-file "$release/.env" -f "$release/compose.yml" config --quiet
docker compose --project-directory "$release" --env-file "$release/.env" -f "$release/compose.yml" pull

rollback() {
  status=$?
  if [[ $status -ne 0 && -n "$previous" && -d "$previous" ]]; then
    echo "deployment failed; restoring $(basename "$previous")" >&2
    ln -sfn "$previous" "$root/current"
    docker compose --project-directory "$previous" --env-file "$previous/.env" -f "$previous/compose.yml" up -d --remove-orphans || true
  fi
  exit "$status"
}
trap rollback EXIT
ln -sfn "$release" "$root/current"
docker compose --project-directory "$release" --env-file "$release/.env" -f "$release/compose.yml" up -d --remove-orphans --wait --wait-timeout 600
curl --fail --silent --show-error --retry 12 --retry-delay 5 --max-time 10 https://www.logitrack.kr/login >/dev/null
printf '%s\n' "$revision" >"$root/deployed-revision"
chmod 0644 "$root/deployed-revision"
trap - EXIT

# Keep the current and previous release directories for a bounded local rollback.
while IFS= read -r stale; do
  [[ "$stale" =~ ^/opt/logitrack/releases/[0-9a-f]{40}$ ]] || { echo "refusing unexpected cleanup target: $stale" >&2; exit 4; }
  rm -rf -- "$stale"
done < <(find "$root/releases" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -nr | tail -n +3 | cut -d' ' -f2-)
echo "deployed $revision"
