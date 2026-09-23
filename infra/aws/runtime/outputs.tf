output "public_url" { value = "https://${var.domain_name}" }
output "instance_id" { value = aws_instance.runtime.id }
output "public_ipv4" { value = aws_eip.runtime.public_ip }
output "deployer_role_arn" { value = aws_iam_role.deployer.arn }
output "snapshot_policy_id" { value = aws_dlm_lifecycle_policy.runtime.id }
output "backup_bucket_name" { value = aws_s3_bucket.backups.id }
output "postgres_backup_association_id" { value = aws_ssm_association.postgres_backup.association_id }
output "system_recovery_alarm_name" { value = aws_cloudwatch_metric_alarm.system_recovery.alarm_name }
output "github_environment_variables" {
  value = { AWS_RUNTIME_ROLE_ARN = aws_iam_role.deployer.arn, AWS_RUNTIME_INSTANCE_ID = aws_instance.runtime.id, AWS_REGION = var.aws_region, AWS_ACCOUNT_ID = data.aws_caller_identity.current.account_id }
}
output "secret_parameter_names" { value = var.secret_parameter_names }
