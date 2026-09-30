output "state_bucket" { value = aws_s3_bucket.state.id }
output "state_keys" { value = sort(tolist(local.state_keys)) }
output "state_kms_key_arn" { value = aws_kms_key.state.arn }
output "backend_access_policy_arn" { value = aws_iam_policy.backend_access.arn }
output "production_plan_role_arn" { value = aws_iam_role.production_plan.arn }
output "backend_configs" {
  value = {
    for key in local.state_keys : split("/", key)[1] => {
      bucket       = aws_s3_bucket.state.id
      key          = key
      region       = var.aws_region
      encrypt      = true
      kms_key_id   = aws_kms_key.state.arn
      use_lockfile = true
    }
  }
}
