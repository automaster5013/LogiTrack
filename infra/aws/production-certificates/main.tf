resource "aws_acm_certificate" "origin" {
  domain_name       = var.origin_hostname
  validation_method = "DNS"
  options { certificate_transparency_logging_preference = "ENABLED" }
  lifecycle { prevent_destroy = true }
}
resource "aws_route53_record" "origin_validation" {
  for_each = { for option in aws_acm_certificate.origin.domain_validation_options : option.domain_name => { name = option.resource_record_name, type = option.resource_record_type, value = option.resource_record_value } }
  zone_id  = var.route53_zone_id
  name     = each.value.name
  type     = each.value.type
  records  = [each.value.value]
  ttl      = 60
}
resource "aws_acm_certificate_validation" "origin" {
  certificate_arn         = aws_acm_certificate.origin.arn
  validation_record_fqdns = [for record in aws_route53_record.origin_validation : record.fqdn]
}
resource "aws_acm_certificate" "viewer" {
  provider          = aws.global
  domain_name       = var.viewer_hostname
  validation_method = "DNS"
  options { certificate_transparency_logging_preference = "ENABLED" }
  lifecycle { prevent_destroy = true }
}
resource "aws_route53_record" "viewer_validation" {
  for_each = { for option in aws_acm_certificate.viewer.domain_validation_options : option.domain_name => { name = option.resource_record_name, type = option.resource_record_type, value = option.resource_record_value } }
  zone_id  = var.route53_zone_id
  name     = each.value.name
  type     = each.value.type
  records  = [each.value.value]
  ttl      = 60
}
resource "aws_acm_certificate_validation" "viewer" {
  provider                = aws.global
  certificate_arn         = aws_acm_certificate.viewer.arn
  validation_record_fqdns = [for record in aws_route53_record.viewer_validation : record.fqdn]
}
resource "aws_cloudwatch_metric_alarm" "origin_expiry" {
  alarm_name          = "logitrack-production-origin-certificate-expiry"
  namespace           = "AWS/CertificateManager"
  metric_name         = "DaysToExpiry"
  statistic           = "Minimum"
  period              = 86400
  evaluation_periods  = 1
  comparison_operator = "LessThanThreshold"
  threshold           = 45
  treat_missing_data  = "breaching"
  alarm_actions       = [var.regional_alarm_topic_arn]
  ok_actions          = [var.regional_alarm_topic_arn]
  dimensions          = { CertificateArn = aws_acm_certificate_validation.origin.certificate_arn }
}
resource "aws_cloudwatch_metric_alarm" "viewer_expiry" {
  provider            = aws.global
  alarm_name          = "logitrack-production-viewer-certificate-expiry"
  namespace           = "AWS/CertificateManager"
  metric_name         = "DaysToExpiry"
  statistic           = "Minimum"
  period              = 86400
  evaluation_periods  = 1
  comparison_operator = "LessThanThreshold"
  threshold           = 45
  treat_missing_data  = "breaching"
  alarm_actions       = [var.global_alarm_topic_arn]
  ok_actions          = [var.global_alarm_topic_arn]
  dimensions          = { CertificateArn = aws_acm_certificate_validation.viewer.certificate_arn }
}
