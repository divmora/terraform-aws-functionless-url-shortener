##   CloudFront in front of the regional API: caches public redirects (/{linkId}, /?go=)
##   at the edge. Mirrors the SAM CloudFrontDistro.

locals {
  api_origin_id = "URLShortenerAPIGW"
}

resource "aws_cloudfront_distribution" "this" {
  comment = "URL Shortener CDN"
  enabled = true

  origin {
    origin_id   = local.api_origin_id
    domain_name = "${aws_api_gateway_rest_api.this.id}.execute-api.${local.region}.amazonaws.com"
    origin_path = "/${aws_api_gateway_stage.prod.stage_name}"

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

  # Custom domain (aliases + ACM certificate) is added in M2.
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = var.tags
}
