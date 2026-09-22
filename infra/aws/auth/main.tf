resource "aws_cognito_user_pool" "operators" {
  name                     = "logitrack-${var.environment}-operators"
  deletion_protection      = "ACTIVE"
  user_pool_tier           = "PLUS"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  mfa_configuration        = "OFF"

  admin_create_user_config { allow_admin_create_user_only = true }
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
  sign_in_policy { allowed_first_auth_factors = ["PASSWORD", "WEB_AUTHN"] }
  web_authn_configuration {
    relying_party_id  = var.auth_domain
    user_verification = "required"
  }
  password_policy {
    minimum_length                   = 16
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 1
  }
  user_pool_add_ons { advanced_security_mode = "ENFORCED" }
  lifecycle { prevent_destroy = true }
}

resource "aws_cognito_user_pool_client" "web" {
  name                                 = "logitrack-${var.environment}-web"
  user_pool_id                         = aws_cognito_user_pool.operators.id
  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "profile"]
  callback_urls                        = [var.callback_url]
  logout_urls                          = [var.logout_url]
  supported_identity_providers         = ["COGNITO"]
  explicit_auth_flows                  = ["ALLOW_USER_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true
  access_token_validity                = 1
  id_token_validity                    = 1
  refresh_token_validity               = 1
  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }
}

# Cognito requires the custom domain's parent to resolve before it will create
# the CloudFront distribution. Replace this TEST-NET address with the runtime
# load-balancer alias when the web stack is provisioned.
resource "aws_route53_record" "apex_validation_placeholder" {
  zone_id = var.hosted_zone_id
  name    = "logitrack.kr"
  type    = "A"
  ttl     = 60
  records = ["192.0.2.1"]
}

resource "aws_cognito_user_pool_domain" "auth" {
  domain                = var.auth_domain
  certificate_arn       = var.certificate_arn
  user_pool_id          = aws_cognito_user_pool.operators.id
  managed_login_version = 2
  depends_on            = [aws_route53_record.apex_validation_placeholder]
}

resource "aws_route53_record" "auth" {
  zone_id = var.hosted_zone_id
  name    = var.auth_domain
  type    = "A"
  alias {
    name                   = aws_cognito_user_pool_domain.auth.cloudfront_distribution
    zone_id                = aws_cognito_user_pool_domain.auth.cloudfront_distribution_zone_id
    evaluate_target_health = false
  }
}

locals {
  roles = { VIEWER = 40, OPERATOR = 30, RECOVERY_OPERATOR = 20, ADMIN = 10 }
}
resource "aws_cognito_user_group" "roles" {
  for_each     = local.roles
  name         = each.key
  description  = "LogiTrack ${each.key} authorization group"
  precedence   = each.value
  user_pool_id = aws_cognito_user_pool.operators.id
}
