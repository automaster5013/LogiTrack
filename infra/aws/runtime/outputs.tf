output "public_url" { value = "https://${var.domain_name}" }
output "instance_id" { value = aws_instance.runtime.id }
output "public_ipv4" { value = aws_eip.runtime.public_ip }
output "deployer_role_arn" { value = aws_iam_role.deployer.arn }
output "github_environment_variables" {
  value = { AWS_RUNTIME_ROLE_ARN = aws_iam_role.deployer.arn, AWS_RUNTIME_INSTANCE_ID = aws_instance.runtime.id, AWS_REGION = var.aws_region, AWS_ACCOUNT_ID = data.aws_caller_identity.current.account_id }
}
output "secret_parameter_names" { value = var.secret_parameter_names }
