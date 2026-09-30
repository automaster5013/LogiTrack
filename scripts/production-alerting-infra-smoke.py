from pathlib import Path

root = Path(__file__).resolve().parents[1]
infra = root / "infra/aws/production-alerting"
main = (infra / "main.tf").read_text()
versions = (infra / "versions.tf").read_text()
variables = (infra / "variables.tf").read_text()
outputs = (infra / "outputs.tf").read_text()

assert 'key          = "production/alerting/terraform.tfstate"' in versions
assert 'region = "us-east-1"' in versions
assert main.count("enable_key_rotation     = true") == 2
assert main.count("deletion_window_in_days = 30") == 2
assert main.count("kms_master_key_id = aws_kms_key.") == 2
assert main.count("prevent_destroy = true") == 4
assert main.count('identifiers = ["cloudwatch.amazonaws.com"]') == 4
assert main.count('variable = "aws:SourceAccount"') == 4
assert "cloudwatch:ap-northeast-2:" in main
assert "cloudwatch:us-east-1:" in main
assert main.count('variable = "aws:SecureTransport"') == 2
assert main.count('protocol                        = "https"') == 2
assert main.count("endpoint                        = var.paging_https_endpoint") == 2
assert "sensitive   = true" in variables
assert "regional_alarm_topic_arn" in outputs
assert "global_alarm_topic_arn" in outputs
assert "paging_subscription_arns" in outputs

print("PASS: production alerting has encrypted, scoped, HTTPS-confirmed regional and global channels")
