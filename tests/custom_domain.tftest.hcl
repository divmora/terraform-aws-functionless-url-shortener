# Custom domain (M2) unit tests with mocked AWS providers.

mock_provider "aws" {
  mock_resource "aws_dynamodb_table" {
    defaults = {
      arn = "arn:aws:dynamodb:ap-south-1:123456789012:table/eg-test-shortener-links"
    }
  }

  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      domain_name    = "d111111abcdef8.cloudfront.net"
      hosted_zone_id = "Z2FDTNDATAQYW2"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

mock_provider "aws" {
  alias = "us_east_1"
}

variables {
  namespace = "eg"
  stage     = "test"
  name      = "shortener"
  org_id    = "o-abc123defg"
}

run "no_domain_uses_default_certificate" {
  command = apply

  assert {
    condition     = length(aws_cloudfront_distribution.this[0].aliases) == 0
    error_message = "No aliases without domain_alias."
  }

  assert {
    condition = (
      one(aws_cloudfront_distribution.this[0].viewer_certificate).cloudfront_default_certificate &&
      one(aws_cloudfront_distribution.this[0].viewer_certificate).acm_certificate_arn == null
    )
    error_message = "The default CloudFront certificate must be used without a custom domain."
  }

  assert {
    condition     = length(aws_route53_record.a) == 0 && length(aws_route53_record.aaaa) == 0
    error_message = "No DNS records without a hosted zone."
  }

  assert {
    condition     = output.dns_target == null && length(output.dns_record_fqdns) == 0
    error_message = "dns_target and dns_record_fqdns must be empty without a custom domain."
  }
}

run "domain_with_certificate" {
  command = apply

  variables {
    domain_alias        = "go.example.com"
    acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/0a1b2c3d-1234-5678-9abc-def012345678"
  }

  assert {
    condition     = aws_cloudfront_distribution.this[0].aliases == toset(["go.example.com"])
    error_message = "CloudFront must serve the alias."
  }

  assert {
    condition = (
      !one(aws_cloudfront_distribution.this[0].viewer_certificate).cloudfront_default_certificate &&
      one(aws_cloudfront_distribution.this[0].viewer_certificate).acm_certificate_arn == var.acm_certificate_arn &&
      one(aws_cloudfront_distribution.this[0].viewer_certificate).ssl_support_method == "sni-only" &&
      one(aws_cloudfront_distribution.this[0].viewer_certificate).minimum_protocol_version == "TLSv1.2_2021"
    )
    error_message = "Viewer certificate must be the ACM cert with SNI and TLSv1.2_2021 (SAM parity)."
  }

  assert {
    condition     = strcontains(local.api_body, "\"shortUrl\":\"https://go.example.com/?go=$inputRoot")
    error_message = "Short URLs must default to https://<domain_alias>."
  }

  assert {
    condition     = output.short_url_base == "https://go.example.com"
    error_message = "short_url_base must use the custom domain."
  }

  assert {
    condition     = output.dns_target == "d111111abcdef8.cloudfront.net"
    error_message = "dns_target must be the CloudFront domain."
  }

  assert {
    condition     = length(aws_route53_record.a) == 0
    error_message = "No DNS records without hosted_zone_id."
  }
}

run "url_prefix_wins_over_domain" {
  command = apply

  variables {
    domain_alias        = "go.example.com"
    acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/0a1b2c3d-1234-5678-9abc-def012345678"
    url_prefix          = "https://sho.rt"
  }

  assert {
    condition     = strcontains(local.api_body, "\"shortUrl\":\"https://sho.rt/?go=$inputRoot") && output.short_url_base == "https://sho.rt"
    error_message = "url_prefix must take precedence over domain_alias (SAM parity)."
  }
}

run "dns_records_with_hosted_zone" {
  command = apply

  variables {
    domain_alias        = "go.example.com"
    acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/0a1b2c3d-1234-5678-9abc-def012345678"
    hosted_zone_id      = "Z0123456789ABCDEFGHIJ"
  }

  assert {
    condition = (
      aws_route53_record.a[0].type == "A" && aws_route53_record.aaaa[0].type == "AAAA" &&
      aws_route53_record.a[0].name == "go.example.com" && aws_route53_record.a[0].zone_id == "Z0123456789ABCDEFGHIJ"
    )
    error_message = "A and AAAA records must be created for the alias in the given zone."
  }

  assert {
    condition = (
      one(aws_route53_record.a[0].alias).name == "d111111abcdef8.cloudfront.net" &&
      one(aws_route53_record.a[0].alias).zone_id == "Z2FDTNDATAQYW2" &&
      !one(aws_route53_record.a[0].alias).evaluate_target_health
    )
    error_message = "Records must alias the CloudFront distribution."
  }
}

run "domain_without_certificate_fails" {
  command = plan

  variables {
    domain_alias = "go.example.com"
  }

  expect_failures = [aws_cloudfront_distribution.this]
}

run "hosted_zone_without_domain_fails" {
  command = plan

  variables {
    hosted_zone_id = "Z0123456789ABCDEFGHIJ"
  }

  expect_failures = [aws_cloudfront_distribution.this]
}

run "rejects_certificate_outside_us_east_1" {
  command = plan

  variables {
    domain_alias        = "go.example.com"
    acm_certificate_arn = "arn:aws:acm:ap-south-1:123456789012:certificate/0a1b2c3d-1234-5678-9abc-def012345678"
  }

  expect_failures = [var.acm_certificate_arn]
}

run "rejects_domain_with_scheme" {
  command = plan

  variables {
    domain_alias = "https://go.example.com"
  }

  expect_failures = [var.domain_alias]
}

run "disabled_creates_no_dns" {
  command = apply

  variables {
    enabled             = false
    domain_alias        = "go.example.com"
    acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/0a1b2c3d-1234-5678-9abc-def012345678"
    hosted_zone_id      = "Z0123456789ABCDEFGHIJ"
  }

  assert {
    condition     = length(aws_route53_record.a) == 0 && length(aws_cloudfront_distribution.this) == 0 && output.dns_target == null
    error_message = "enabled = false must create nothing, including DNS records."
  }
}
