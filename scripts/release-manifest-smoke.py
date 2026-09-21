import argparse
import json
import re
from pathlib import Path


SERVICES = ("api", "analytics", "simulator", "web", "otel-collector")
DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")
REVISION = re.compile(r"^[0-9a-f]{40}$")
ACCOUNT_ID = re.compile(r"^[0-9]{12}$")
REGION = re.compile(r"^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--account-id", required=True)
    parser.add_argument("--region", required=True)
    parser.add_argument("--registry", required=True)
    parser.add_argument("--repository-prefix", required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if not REVISION.fullmatch(args.revision):
        raise AssertionError("revision must be a full lowercase Git SHA")
    if not ACCOUNT_ID.fullmatch(args.account_id):
        raise AssertionError("account ID must contain exactly 12 digits")
    if not REGION.fullmatch(args.region):
        raise AssertionError("AWS region is invalid")

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    expected_top_level = {
        "schemaVersion",
        "revision",
        "awsAccountId",
        "awsRegion",
        "images",
    }
    if set(manifest) != expected_top_level or manifest["schemaVersion"] != 1:
        raise AssertionError("release manifest schema is invalid")
    if manifest["revision"] != args.revision:
        raise AssertionError("release manifest revision does not match")
    if manifest["awsAccountId"] != args.account_id or manifest["awsRegion"] != args.region:
        raise AssertionError("release manifest AWS boundary does not match")

    images = manifest["images"]
    if not isinstance(images, list) or [image.get("service") for image in images] != list(SERVICES):
        raise AssertionError("release manifest must contain each service exactly once in stable order")
    for image in images:
        if set(image) != {"service", "repository", "digest", "uri"}:
            raise AssertionError("release manifest image schema is invalid")
        service = image["service"]
        repository = f"{args.repository_prefix}/{service}"
        digest = image["digest"]
        if image["repository"] != repository or not DIGEST.fullmatch(digest):
            raise AssertionError(f"release manifest image identity is invalid: {service}")
        if image["uri"] != f"{args.registry}/{repository}@{digest}":
            raise AssertionError(f"release manifest image URI is not digest-pinned: {service}")

    print("PASS: staging release manifest contains five verified digest-pinned images")


if __name__ == "__main__":
    main()
