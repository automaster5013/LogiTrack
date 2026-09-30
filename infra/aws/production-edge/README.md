# Production viewer edge

This validation-only Terraform root connects the production ALB to `www.logitrack.kr` through CloudFront. It creates the `origin.logitrack.kr` alias, an HTTPS-only TLS 1.2 custom origin with the same secret header pair required by `production-compute`, a no-cache dynamic behavior that forwards all viewer authentication context, HTTP/2 and HTTP/3, IPv4/IPv6 viewer aliases, TLS 1.2 viewer policy, global AWS WAF managed rules, per-viewer-IP rate limiting, global 5xx/WAF alarms, and retain-on-delete protection for the distribution.

The viewer certificate must already be validated in `us-east-1`; the ALB origin certificate must already cover `origin.logitrack.kr` in Seoul. `global_alarm_topic_arn` must be a separately operated `us-east-1` SNS topic because CloudFront metrics are global. Both secret header inputs persist in the KMS-encrypted protected remote state and must exactly match the active name and value accepted by `production-compute`.

This root deliberately disables CloudFront caching for every response. The application carries access tokens in secure cookies and serves personalized operational data; enabling caching requires a separate threat model, cache-key proof, and authenticated-response tests. The CloudFront custom origin header overwrites a viewer-supplied value before the request reaches the ALB.

Do not apply until the production budget, viewer and origin certificates, global alarm receiver, data/compute roots, migration rehearsal, failover/load drills, and cutover approval are complete. Apply in this order: allow `[old, new]` values in the compute root, set `new` here, verify the distribution and direct-origin 403 behavior, then remove `old` from compute. A header-name rotation requires an approved maintenance window.

```bash
terraform -chdir=infra/aws/production-edge fmt -check
terraform -chdir=infra/aws/production-edge init -backend=false -input=false
terraform -chdir=infra/aws/production-edge validate
python scripts/production-edge-infra-smoke.py
```

References: [restrict ALB access to CloudFront](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/restrict-access-to-load-balancer.html), [origin custom headers](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/add-origin-custom-headers.html), and [AWS managed WAF rule groups](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-list.html).
