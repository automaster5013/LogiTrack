resource "aws_route53_record" "origin" {
  zone_id = var.route53_zone_id
  name    = var.origin_hostname
  type    = "A"
  alias {
    name                   = var.load_balancer_dns_name
    zone_id                = var.load_balancer_zone_id
    evaluate_target_health = true
  }
}

resource "aws_cloudfront_cache_policy" "dynamic" {
  name        = "logitrack-production-dynamic-no-cache"
  comment     = "Authorization-sensitive application responses must never be cached."
  default_ttl = 0
  max_ttl     = 0
  min_ttl     = 0
  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
    cookies_config { cookie_behavior = "none" }
    headers_config { header_behavior = "none" }
    query_strings_config { query_string_behavior = "none" }
  }
}

resource "aws_cloudfront_origin_request_policy" "application" {
  name    = "logitrack-production-all-viewer"
  comment = "Forward authentication, CSRF, query, and cookie context to the application origin."
  cookies_config { cookie_behavior = "all" }
  headers_config { header_behavior = "allViewer" }
  query_strings_config { query_string_behavior = "all" }
}

resource "aws_wafv2_web_acl" "viewer" {
  provider = aws.global
  name     = "logitrack-production-viewer"
  scope    = "CLOUDFRONT"
  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = {
      common = { priority = 10, name = "AWSManagedRulesCommonRuleSet" }
      bad    = { priority = 20, name = "AWSManagedRulesKnownBadInputsRuleSet" }
      ip     = { priority = 30, name = "AWSManagedRulesAmazonIpReputationList" }
    }
    content {
      name     = "aws-${rule.key}"
      priority = rule.value.priority
      override_action {
        none {}
      }
      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = "AWS"
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "logitrack-viewer-${rule.key}"
        sampled_requests_enabled   = true
      }
    }
  }

  rule {
    name     = "per-viewer-ip-rate-limit"
    priority = 40
    action {
      block {}
    }
    statement {
      rate_based_statement {
        aggregate_key_type = "IP"
        limit              = var.waf_requests_per_five_minutes
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "logitrack-viewer-rate-limit"
      sampled_requests_enabled   = true
    }
  }
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "logitrack-production-viewer"
    sampled_requests_enabled   = true
  }
}

resource "aws_cloudfront_distribution" "production" {
  enabled          = true
  is_ipv6_enabled  = true
  retain_on_delete = true
  comment          = "LogiTrack production viewer edge"
  aliases          = [var.public_hostname]
  http_version     = "http2and3"
  price_class      = "PriceClass_200"
  web_acl_id       = aws_wafv2_web_acl.viewer.arn

  origin {
    domain_name = var.origin_hostname
    origin_id   = "production-alb"
    custom_header {
      name  = var.origin_verify_header_name
      value = var.origin_verify_header_value
    }
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "https-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_keepalive_timeout = 5
      origin_read_timeout      = 30
    }
  }

  default_cache_behavior {
    target_origin_id         = "production-alb"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = true
    cache_policy_id          = aws_cloudfront_cache_policy.dynamic.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.application.id
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }
  viewer_certificate {
    acm_certificate_arn      = var.viewer_certificate_arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }
  depends_on = [aws_route53_record.origin]
}

resource "aws_route53_record" "viewer_ipv4" {
  zone_id = var.route53_zone_id
  name    = var.public_hostname
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.production.domain_name
    zone_id                = aws_cloudfront_distribution.production.hosted_zone_id
    evaluate_target_health = false
  }
}
resource "aws_route53_record" "viewer_ipv6" {
  zone_id = var.route53_zone_id
  name    = var.public_hostname
  type    = "AAAA"
  alias {
    name                   = aws_cloudfront_distribution.production.domain_name
    zone_id                = aws_cloudfront_distribution.production.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_cloudwatch_metric_alarm" "viewer_5xx" {
  provider            = aws.global
  alarm_name          = "logitrack-production-cloudfront-5xx-rate"
  namespace           = "AWS/CloudFront"
  metric_name         = "5xxErrorRate"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.global_alarm_topic_arn]
  ok_actions          = [var.global_alarm_topic_arn]
  dimensions = {
    DistributionId = aws_cloudfront_distribution.production.id
    Region         = "Global"
  }
}
resource "aws_cloudwatch_metric_alarm" "waf_blocks" {
  provider            = aws.global
  alarm_name          = "logitrack-production-viewer-waf-blocks"
  namespace           = "AWS/WAFV2"
  metric_name         = "BlockedRequests"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 100
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.global_alarm_topic_arn]
  ok_actions          = [var.global_alarm_topic_arn]
  dimensions = {
    WebACL = aws_wafv2_web_acl.viewer.name
    Region = "Global"
  }
}
