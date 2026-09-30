output "distribution_id" { value = aws_cloudfront_distribution.production.id }
output "distribution_domain_name" { value = aws_cloudfront_distribution.production.domain_name }
output "viewer_hostname" { value = aws_route53_record.viewer_ipv4.fqdn }
output "origin_hostname" { value = aws_route53_record.origin.fqdn }
