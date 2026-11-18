provider "aws" {
  region = var.region
}

# CloudFront metrics exist only in us-east-1; the module creates CloudFront alarms there.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "url_shortener" {
  source = "../../"

  org_id     = var.org_id
  url_prefix = var.url_prefix

  domain_alias        = var.domain_alias
  acm_certificate_arn = var.acm_certificate_arn
  hosted_zone_id      = var.hosted_zone_id

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  context = module.this.context
}
