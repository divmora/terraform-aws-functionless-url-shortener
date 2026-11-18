##   CloudFront in front of the regional API: caches public redirects (/{linkId}, /?go=)
##   at the edge. Mirrors the SAM CloudFrontDistro.

locals {
  api_origin_id = "URLShortenerAPIGW"
}

resource "aws_cloudfront_distribution" "this" {
  count = local.enabled ? 1 : 0

  comment = "URL Shortener CDN"
  enabled = true

  # CloudFormation defaults used by the SAM template (verified against a live SAM stack).
  http_version    = "http1.1"
  is_ipv6_enabled = true

  origin {
    origin_id   = local.api_origin_id
    domain_name = "${aws_api_gateway_rest_api.this[0].id}.execute-api.${local.region}.amazonaws.com"
    origin_path = "/${aws_api_gateway_stage.prod[0].stage_name}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      # API Gateway only negotiates TLS 1.2+, so older origin protocols are never used.
      origin_ssl_protocols = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = local.api_origin_id
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 31536000

    forwarded_values {
      query_string            = true
      query_string_cache_keys = ["go"]
      headers = [
        "Access-Control-Request-Headers",
        "Access-Control-Request-Method",
        "Origin",
        "Authorization",
      ]

      cookies {
        forward = "none"
      }
    }
  }

  custom_error_response {
    error_code            = 400
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 403
    error_caching_min_ttl = 1
  }

  custom_error_response {
    error_code            = 500
    error_caching_min_ttl = 5
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  aliases = local.has_domain_alias ? [var.domain_alias] : []

  viewer_certificate {
    cloudfront_default_certificate = !local.has_domain_alias
    acm_certificate_arn            = local.has_domain_alias ? var.acm_certificate_arn : null
    ssl_support_method             = local.has_domain_alias ? "sni-only" : null
    minimum_protocol_version       = local.has_domain_alias ? "TLSv1.2_2021" : "TLSv1"
  }

  tags = module.cdn_label.tags

  lifecycle {
    # Replaces the SAM template Rules (Terraform 1.6 can't compare variables in validation blocks).
    precondition {
      condition     = !local.has_domain_alias || var.acm_certificate_arn != ""
      error_message = "The acm_certificate_arn is required when domain_alias is set."
    }

    precondition {
      condition     = var.hosted_zone_id == "" || local.has_domain_alias
      error_message = "The domain_alias is required when hosted_zone_id is set."
    }
  }
}
