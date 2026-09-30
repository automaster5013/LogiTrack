#!/usr/bin/env python3
import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

ORDER = ["state", "alerting", "audit", "certificates", "data", "compute", "edge"]
SHA = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
ACCOUNT = re.compile(r"^[0-9]{12}$")
REPOSITORY = Path(__file__).resolve().parents[1]
STATE_KEYS = {
    "production/alerting/terraform.tfstate",
    "production/audit/terraform.tfstate",
    "production/certificates/terraform.tfstate",
    "production/data/terraform.tfstate",
    "production/compute/terraform.tfstate",
    "production/edge/terraform.tfstate",
}


def load(path: Path, label: str) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read {label}: {exc}") from exc
    if not isinstance(value, dict):
        raise ValueError(f"{label} root must be an object")
    return value


def atomic_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")
        temporary = Path(stream.name)
    temporary.replace(path)


def output_value(outputs: dict, name: str):
    item = outputs.get(name)
    if not isinstance(item, dict) or "value" not in item:
        raise ValueError(f"Terraform output is missing {name}")
    return item["value"]


def run_json(command: list[str]) -> dict:
    result = subprocess.run(command, check=False, capture_output=True, text=True)
    if result.returncode != 0:
        raise ValueError(f"live verification command failed: {' '.join(command[:4])}")
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise ValueError("live verification returned invalid JSON") from exc
    if not isinstance(value, dict):
        raise ValueError("live verification response must be an object")
    return value


def aws(region: str, *arguments: str) -> dict:
    return run_json(["aws", "--region", region, *arguments, "--output", "json"])


def terraform_outputs(root: str) -> dict:
    return run_json(["terraform", f"-chdir={REPOSITORY / 'infra/aws' / f'production-{root}'}", "output", "-json"])


def collect(root: str, outputs: dict, now: datetime) -> dict:
    if root == "state":
        bucket = output_value(outputs, "state_bucket")
        key_arn = output_value(outputs, "state_kms_key_arn")
        return {
            "versioning": aws("ap-northeast-2", "s3api", "get-bucket-versioning", "--bucket", bucket).get("Status"),
            "public_access_block": aws("ap-northeast-2", "s3api", "get-public-access-block", "--bucket", bucket).get("PublicAccessBlockConfiguration"),
            "kms_rotation": aws("ap-northeast-2", "kms", "get-key-rotation-status", "--key-id", key_arn).get("KeyRotationEnabled"),
        }
    if root == "alerting":
        topics = {"regional": output_value(outputs, "regional_alarm_topic_arn"), "global": output_value(outputs, "global_alarm_topic_arn")}
        result = {}
        for name, topic in topics.items():
            region = "ap-northeast-2" if name == "regional" else "us-east-1"
            attributes = aws(region, "sns", "get-topic-attributes", "--topic-arn", topic).get("Attributes", {})
            subscriptions = aws(region, "sns", "list-subscriptions-by-topic", "--topic-arn", topic).get("Subscriptions", [])
            result[name] = {
                "kms_key_id": attributes.get("KmsMasterKeyId"),
                "confirmed_https_subscriptions": sum(1 for item in subscriptions if item.get("Protocol") == "https" and item.get("SubscriptionArn") not in (None, "PendingConfirmation")),
            }
        return result
    if root == "audit":
        trail = aws("ap-northeast-2", "cloudtrail", "get-trail-status", "--name", output_value(outputs, "trail_arn"))
        lock = aws("ap-northeast-2", "s3api", "get-object-lock-configuration", "--bucket", output_value(outputs, "audit_bucket_name")).get("ObjectLockConfiguration", {})
        retention = lock.get("Rule", {}).get("DefaultRetention", {})
        return {"is_logging": trail.get("IsLogging"), "latest_delivery_error": trail.get("LatestDeliveryError", ""), "object_lock": lock.get("ObjectLockEnabled"), "retention_mode": retention.get("Mode"), "retention_days": retention.get("Days")}
    if root == "certificates":
        result = {}
        for name, region in (("origin", "ap-northeast-2"), ("viewer", "us-east-1")):
            cert = aws(region, "acm", "describe-certificate", "--certificate-arn", output_value(outputs, f"{name}_certificate_arn")).get("Certificate", {})
            expiry = datetime.fromisoformat(str(cert.get("NotAfter", "")).replace("Z", "+00:00")).astimezone(timezone.utc)
            result[name] = {"status": cert.get("Status"), "days_remaining": int((expiry - now).total_seconds() // 86400)}
        return result
    if root == "data":
        database = aws("ap-northeast-2", "rds", "describe-db-instances", "--db-instance-identifier", output_value(outputs, "database_identifier")).get("DBInstances", [{}])[0]
        cache = aws("ap-northeast-2", "elasticache", "describe-replication-groups", "--replication-group-id", output_value(outputs, "cache_replication_group_id")).get("ReplicationGroups", [{}])[0]
        kafka = aws("ap-northeast-2", "kafka", "describe-cluster-v2", "--cluster-arn", output_value(outputs, "kafka_cluster_arn")).get("ClusterInfo", {})
        return {"database": {"status": database.get("DBInstanceStatus"), "multi_az": database.get("MultiAZ"), "encrypted": database.get("StorageEncrypted")}, "cache": {"status": cache.get("Status"), "automatic_failover": cache.get("AutomaticFailover")}, "kafka": {"state": kafka.get("State")}}
    if root == "compute":
        services = aws("ap-northeast-2", "ecs", "describe-services", "--cluster", output_value(outputs, "ecs_cluster_arn"), "--services", output_value(outputs, "api_service_name"), output_value(outputs, "web_service_name")).get("services", [])
        service_checks = [{"status": item.get("status"), "desired": item.get("desiredCount"), "running": item.get("runningCount"), "rollout": next((deployment.get("rolloutState") for deployment in item.get("deployments", []) if deployment.get("status") == "PRIMARY"), None)} for item in services]
        health = aws("ap-northeast-2", "elbv2", "describe-target-health", "--target-group-arn", output_value(outputs, "web_target_group_arn")).get("TargetHealthDescriptions", [])
        targets = [item.get("TargetHealth", {}).get("State") for item in health]
        load_balancers = aws("ap-northeast-2", "elbv2", "describe-load-balancers", "--load-balancer-arns", output_value(outputs, "load_balancer_arn")).get("LoadBalancers", [])
        return {"services": service_checks, "web_targets": targets, "load_balancer_state": load_balancers[0].get("State", {}).get("Code") if load_balancers else None}
    if root == "edge":
        distribution = aws("us-east-1", "cloudfront", "get-distribution", "--id", output_value(outputs, "distribution_id")).get("Distribution", {})
        config = distribution.get("DistributionConfig", {})
        return {"status": distribution.get("Status"), "enabled": config.get("Enabled"), "web_acl_id": config.get("WebACLId"), "aliases": config.get("Aliases", {}).get("Items", [])}
    raise ValueError(f"unsupported root: {root}")


def verify(root: str, outputs: dict, observations: dict) -> list[str]:
    checks = []
    def require(condition: bool, message: str) -> None:
        if not condition:
            raise ValueError(message)
        checks.append(message)

    if root == "state":
        require(set(output_value(outputs, "state_keys")) == STATE_KEYS, "six exact backend state keys are present")
        require(observations.get("versioning") == "Enabled", "state bucket versioning is enabled")
        block = observations.get("public_access_block", {})
        require(all(block.get(name) is True for name in ("BlockPublicAcls", "IgnorePublicAcls", "BlockPublicPolicy", "RestrictPublicBuckets")), "state bucket public access is fully blocked")
        require(observations.get("kms_rotation") is True, "state KMS rotation is enabled")
    elif root == "alerting":
        for name in ("regional", "global"):
            item = observations.get(name, {})
            require(bool(item.get("kms_key_id")), f"{name} alarm topic is KMS encrypted")
            require(item.get("confirmed_https_subscriptions", 0) >= 1, f"{name} HTTPS paging subscription is confirmed")
    elif root == "audit":
        require(observations.get("is_logging") is True, "CloudTrail is logging")
        require(not observations.get("latest_delivery_error"), "CloudTrail has no delivery error")
        require(observations.get("object_lock") == "Enabled", "audit Object Lock is enabled")
        require(observations.get("retention_mode") == "COMPLIANCE" and observations.get("retention_days", 0) >= 400, "audit compliance retention is at least 400 days")
    elif root == "certificates":
        for name in ("origin", "viewer"):
            item = observations.get(name, {})
            require(item.get("status") == "ISSUED", f"{name} certificate is issued")
            require(item.get("days_remaining", 0) >= 45, f"{name} certificate has at least 45 days remaining")
    elif root == "data":
        database = observations.get("database", {})
        require(database.get("status") == "available" and database.get("multi_az") is True and database.get("encrypted") is True, "database is available, Multi-AZ, and encrypted")
        cache = observations.get("cache", {})
        require(cache.get("status") == "available" and cache.get("automatic_failover") == "enabled", "cache is available with automatic failover")
        require(observations.get("kafka", {}).get("state") == "ACTIVE", "Kafka cluster is active")
    elif root == "compute":
        services = observations.get("services", [])
        require(len(services) == 2, "both ECS services are present")
        require(all(item.get("status") == "ACTIVE" and item.get("desired", 0) > 0 and item.get("running") == item.get("desired") and item.get("rollout") == "COMPLETED" for item in services), "both ECS services are stable at desired count")
        states = observations.get("web_targets", [])
        require(bool(states) and all(state == "healthy" for state in states), "all web targets are healthy")
        require(observations.get("load_balancer_state") == "active", "load balancer is active")
    elif root == "edge":
        require(observations.get("status") == "Deployed" and observations.get("enabled") is True, "CloudFront distribution is deployed and enabled")
        require(bool(observations.get("web_acl_id")), "CloudFront WAF is attached")
        require("www.logitrack.kr" in observations.get("aliases", []), "CloudFront viewer alias is configured")
    return checks


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify a just-applied production Terraform root and advance its verification receipt.")
    parser.add_argument("--root", required=True, choices=ORDER)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--account-id", required=True)
    parser.add_argument("--ledger", required=True, type=Path)
    parser.add_argument("--receipt", required=True, type=Path)
    parser.add_argument("--snapshot", type=Path, help="Test-only JSON containing outputs and observations")
    parser.add_argument("--now", help="Test-only RFC3339 UTC clock")
    args = parser.parse_args()
    try:
        if not SHA.fullmatch(args.revision) or not ACCOUNT.fullmatch(args.account_id):
            raise ValueError("revision or AWS account ID is invalid")
        if args.receipt.exists():
            raise ValueError("verification receipt already exists; receipts are immutable")
        if bool(args.snapshot) != bool(args.now):
            raise ValueError("test mode requires both --snapshot and --now")
        if args.snapshot and (args.revision != "a" * 40 or args.account_id != "123456789012"):
            raise ValueError("test snapshots are restricted to the fixed smoke-test identity")
        ledger = load(args.ledger, "apply ledger")
        completed = ledger.get("completed")
        if ledger.get("schema_version") != 1 or ledger.get("revision") != args.revision or not isinstance(completed, list) or not completed:
            raise ValueError("apply ledger schema, revision, or entries are invalid")
        roots = [item.get("root") for item in completed if isinstance(item, dict)]
        if roots != ORDER[: len(roots)] or roots[-1] != args.root:
            raise ValueError("only the most recently applied root can be verified")
        if any(item.get("revision") != args.revision or not SHA256.fullmatch(str(item.get("sha256", ""))) or not SHA256.fullmatch(str(item.get("manifest_sha256", ""))) or not str(item.get("applied_at", "")).endswith("Z") for item in completed):
            raise ValueError("apply ledger entries are malformed")
        if any(not item.get("verified_at") or not SHA256.fullmatch(str(item.get("receipt_sha256", ""))) for item in completed[:-1]):
            raise ValueError("every prior root requires a valid verification receipt")
        current = completed[-1]
        if current.get("verified_at") or current.get("receipt_sha256"):
            raise ValueError("the most recently applied root is already verified")

        now = datetime.fromisoformat(args.now.replace("Z", "+00:00")) if args.now else datetime.now(timezone.utc)
        if args.snapshot:
            snapshot = load(args.snapshot, "verification snapshot")
            outputs = snapshot.get("outputs")
            observations = snapshot.get("observations")
            if not isinstance(outputs, dict) or not isinstance(observations, dict):
                raise ValueError("verification snapshot requires outputs and observations objects")
        else:
            identity = aws("ap-northeast-2", "sts", "get-caller-identity")
            if identity.get("Account") != args.account_id:
                raise ValueError("active AWS account does not match --account-id")
            outputs = terraform_outputs(args.root)
            observations = collect(args.root, outputs, now)

        checks = verify(args.root, outputs, observations)
        receipt = {
            "schema_version": 1,
            "root": args.root,
            "revision": args.revision,
            "account_id": args.account_id,
            "applied_plan_sha256": current.get("sha256"),
            "manifest_sha256": current.get("manifest_sha256"),
            "verified_at": now.astimezone(timezone.utc).isoformat().replace("+00:00", "Z"),
            "checks": checks,
        }
        atomic_json(args.receipt, receipt)
        receipt_digest = hashlib.sha256(args.receipt.read_bytes()).hexdigest()
        current["verified_at"] = receipt["verified_at"]
        current["receipt_sha256"] = receipt_digest
        atomic_json(args.ledger, ledger)
        print(f"PASS: production-{args.root} live state verified and receipt recorded")
        return 0
    except (ValueError, TypeError, IndexError, KeyError, subprocess.CalledProcessError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
