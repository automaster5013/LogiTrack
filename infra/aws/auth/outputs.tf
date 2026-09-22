output "user_pool_id" { value = aws_cognito_user_pool.operators.id }
output "issuer_uri" { value = "https://${aws_cognito_user_pool.operators.endpoint}" }
output "client_id" { value = aws_cognito_user_pool_client.web.id }
output "authorization_base_url" { value = "https://${var.auth_domain}" }
output "role_groups" { value = sort(keys(aws_cognito_user_group.roles)) }
