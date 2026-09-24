from pathlib import Path
import re
import sys
import yaml

root = Path(__file__).resolve().parents[1]
tf = (root / "infra/aws/runtime/main.tf").read_text(encoding="utf-8")
compose = yaml.safe_load((root / "deploy/staging/compose.yml").read_text(encoding="utf-8"))
workflow = (root / ".github/workflows/deploy-staging.yml").read_text(encoding="utf-8") if (root / ".github/workflows/deploy-staging.yml").exists() else ""
deploy_script = (root / "scripts/deploy-staging.sh").read_text(encoding="utf-8")

errors = []
for forbidden in ("aws_nat_gateway", "aws_lb\"", "aws_db_instance", "aws_msk_cluster"):
    if forbidden in tf:
        errors.append(f"forbidden fixed-cost resource found: {forbidden}")
if not re.search(r'http_tokens\s*=\s*"required"', tf) or not re.search(r"prevent_destroy\s*=\s*true", tf):
    errors.append("instance must require IMDSv2 and prevent accidental destruction")
for recovery_control in (
    "disable_api_termination              = true",
    'instance_initiated_shutdown_behavior = "stop"',
    'resource "aws_cloudwatch_metric_alarm" "system_recovery"',
    'metric_name         = "StatusCheckFailed_System"',
    'datapoints_to_alarm = 2',
    'alarm_actions       = ["arn:aws:automate:${var.aws_region}:ec2:recover"]',
    'treat_missing_data  = "notBreaching"',
):
    if recovery_control not in tf:
        errors.append(f"EC2 termination or system recovery control is missing: {recovery_control}")
if 'from_port = 22' in tf or 'to_port = 5432' in tf or 'to_port = 9092' in tf:
    errors.append("SSH or a data-tier port is publicly reachable")
if 'monthly_budget_usd == 70' not in (root / "infra/aws/runtime/variables.tf").read_text():
    errors.append("USD 70 budget ceiling validation is missing")
for snapshot_control in (
    'resource "aws_dlm_lifecycle_policy" "runtime"',
    'SnapshotSchedule = "logitrack-staging-daily"',
    'resource_types = ["VOLUME"]',
    'state              = "ENABLED"',
    'retain_rule { count = 7 }',
    'interval      = 24',
    'interval_unit = "HOURS"',
    'times         = ["18:00"]',
    "copy_tags = true",
    'BackupType = "crash-consistent"',
    'identifiers = ["dlm.amazonaws.com"]',
):
    if snapshot_control not in tf:
        errors.append(f"daily seven-copy EBS snapshot control is missing: {snapshot_control}")
if 'Name       = "logitrack-staging-daily"' in tf:
    errors.append("DLM must not add a Name tag that duplicates the copied source-volume Name tag")
for backup_control in (
    'resource "aws_s3_bucket" "backups"',
    "force_destroy = false",
    "lifecycle { prevent_destroy = true }",
    'sse_algorithm = "AES256"',
    'block_public_acls       = true',
    'restrict_public_buckets = true',
    'expiration { days = 8 }',
    'schedule_expression         = "cron(30 18 * * ? *)"',
    'apply_only_at_cron_interval = true',
    'actions   = ["s3:PutObject", "s3:GetObject"]',
    '--sse AES256',
    '--checksum-algorithm SHA256',
    'pg_dump --format=custom',
    'pg_restore --list',
    'pg_restore --exit-on-error --no-owner --no-privileges',
    'information_schema.tables',
    'dropdb --if-exists --force',
):
    if backup_control not in tf:
        errors.append(f"encrypted off-host PostgreSQL backup control is missing: {backup_control}")

services = compose.get("services", {})
if set(services["caddy"].get("ports", [])) != {"80:80", "443:443"}:
    errors.append("only Caddy may publish 80 and 443")
for name, service in services.items():
    if name != "caddy" and service.get("ports"):
        errors.append(f"{name} publishes a host port")
    image = service.get("image", "")
    if image and "${" not in image and not re.search(r"@sha256:[0-9a-f]{64}$", image):
        errors.append(f"{name} image is not digest pinned")
    for mount in service.get("tmpfs", []):
        if not mount.startswith("/"):
            errors.append(f"{name} has an invalid tmpfs mount: {mount}")
for network in ("data",):
    if not compose["networks"][network].get("internal"):
        errors.append(f"{network} network must be internal")
storage_init = services.get("kafka-storage-init", {})
if storage_init.get("user") != "0:0" or storage_init.get("cap_add") != ["CHOWN"]:
    errors.append("Kafka storage initialization must be limited to the CHOWN capability")
if services["kafka"].get("depends_on", {}).get("kafka-storage-init", {}).get("condition") != "service_completed_successfully":
    errors.append("Kafka must wait for its storage ownership initialization")
if services["web"].get("environment", {}).get("AUTH_REQUIRED") != "true":
    errors.append("staging web console must require operator authentication")
if "id-token: write" not in workflow or "AWS-RunShellScript" not in workflow:
    errors.append("deployment workflow must use OIDC and SSM Run Command")
if "fetch-depth: 0" not in workflow:
    errors.append("deployment workflow must fetch history before validating an earlier release revision")
if "/bin/bash /tmp/logitrack-deploy/scripts/deploy-staging.sh" not in workflow:
    errors.append("deployment workflow must not depend on a Windows checkout executable bit")
if 'actions = ["ecr:DescribeImages"]' not in tf:
    errors.append("deployment role must be able to verify the five manifest digests")
if "secrets." in workflow:
    errors.append("deployment workflow must not consume long-lived GitHub secrets")
for boundary in ("SECURE OPERATOR ACCESS", "운영자 로그인", "token_exchange_failed", "인증 서버가 로그인을 완료하지 못했습니다", "다시 로그인하기", "unknown authentication errors must not be rendered as trusted operator guidance", "/console", "returnTo=%2Fconsole", "/api/runtime-version", "jq -e", "cache-control: .*no-store"):
    if boundary not in workflow:
        errors.append(f"post-deployment public verification is missing application boundary: {boundary}")
if deploy_script.count("docker compose --progress quiet") < 3:
    errors.append("deployment pull, start, and rollback must bound SSM output with quiet Compose progress")
if "--retry-all-errors" not in deploy_script or "--connect-timeout" not in deploy_script:
    errors.append("public readiness must tolerate bounded first-certificate provisioning failures")

if errors:
    print("\n".join(f"ERROR: {e}" for e in errors), file=sys.stderr)
    raise SystemExit(1)
print("runtime infrastructure boundaries validated")
