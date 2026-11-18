##   Route 53 alias records for the custom domain (optional). Mirrors SAM DomainRecordA/AAAA.

resource "aws_route53_record" "a" {
  count = local.create_dns ? 1 : 0

  zone_id = var.hosted_zone_id
  name    = var.domain_alias
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.this[0].domain_name
    zone_id                = aws_cloudfront_distribution.this[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "aaaa" {
  count = local.create_dns ? 1 : 0

  zone_id = var.hosted_zone_id
  name    = var.domain_alias
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.this[0].domain_name
    zone_id                = aws_cloudfront_distribution.this[0].hosted_zone_id
    evaluate_target_health = false
  }
}
