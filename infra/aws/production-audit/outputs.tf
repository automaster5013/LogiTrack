output "trail_arn" { value = aws_cloudtrail.audit.arn }
output "audit_bucket_name" { value = aws_s3_bucket.audit.id }
output "audit_log_group_name" { value = aws_cloudwatch_log_group.audit.name }
