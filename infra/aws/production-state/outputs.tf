output "state_bucket" { value = aws_s3_bucket.state.id }
output "state_key" { value = var.state_key }
output "state_kms_key_arn" { value = aws_kms_key.state.arn }
output "backend_access_policy_arn" { value = aws_iam_policy.backend_access.arn }
output "backend_config" {
  value = {
    bucket       = aws_s3_bucket.state.id
    key          = var.state_key
    region       = var.aws_region
    encrypt      = true
    kms_key_id   = aws_kms_key.state.arn
    use_lockfile = true
  }
}
