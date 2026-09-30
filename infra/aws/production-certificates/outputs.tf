output "origin_certificate_arn" { value = aws_acm_certificate_validation.origin.certificate_arn }
output "viewer_certificate_arn" { value = aws_acm_certificate_validation.viewer.certificate_arn }
