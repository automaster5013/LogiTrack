from pathlib import Path

root = Path(__file__).resolve().parents[1]
infra = root / "infra/aws/production-audit"
main = (infra / "main.tf").read_text()
versions = (infra / "versions.tf").read_text()
variables = (infra / "variables.tf").read_text()

assert 'key          = "production/audit/terraform.tfstate"' in versions
assert "is_multi_region_trail         = true" in main
assert "include_global_service_events = true" in main
assert "enable_log_file_validation    = true" in main
assert 'read_write_type           = "All"' in main
assert "enable_key_rotation     = true" in main
assert 'identifiers = ["cloudtrail.amazonaws.com"]' in main
assert 'variable = "aws:SourceArn"' in main
assert 'object_lock_enabled = true' in main
assert 'mode = "COMPLIANCE"' in main
assert "days = var.archive_retention_days" in main
assert main.count("prevent_destroy = true") == 4
assert "GLACIER_IR" in main
assert "retention_in_days = 400" in main
assert 'metric_name         = "RootUsage"' in main
assert 'metric_name         = "AccessDenied"' in main
assert main.count("alarm_actions       = [var.regional_alarm_topic_arn]") == 2
assert "archive_retention_days >= 400" in variables

print("PASS: production audit has immutable, encrypted, multi-region management-event evidence and security paging")
