# Production TLS certificates

This validation-only root provisions two narrowly scoped public ACM certificates through Route 53 DNS validation: `origin.logitrack.kr` in Seoul for the ALB/CloudFront origin connection, and `www.logitrack.kr` in `us-east-1` for CloudFront viewers. Both enable certificate-transparency logging, retain their DNS renewal records, block Terraform destruction, and alarm the region-matched operations topic at fewer than 45 days remaining.

Apply this root after the protected remote-state bootstrap and alarm topics, but before `production-compute` and `production-edge`. Pass `origin_certificate_arn` into the compute root and `viewer_certificate_arn` into the edge root. ACM-managed renewal still depends on the certificates remaining in use and their validation CNAME records remaining publicly resolvable; never delete or rewrite those records during DNS cutover.

This root creates ongoing CloudWatch alarm evaluations and must not be applied until the production budget, domain ownership, Route 53 zone, and both alarm receivers are approved. The `prevent_destroy` guards require an explicit reviewed code change before certificate retirement or replacement.

```bash
terraform -chdir=infra/aws/production-certificates fmt -check
terraform -chdir=infra/aws/production-certificates init -backend=false -input=false
terraform -chdir=infra/aws/production-certificates validate
python scripts/production-certificates-infra-smoke.py
```

References: [ACM DNS validation](https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html), [CloudFront certificate Region](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cnames-and-https-requirements.html), and [ACM DaysToExpiry metric](https://docs.aws.amazon.com/acm/latest/userguide/cloudwatch-metrics.html).
