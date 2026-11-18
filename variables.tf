# Naming, tagging and the `enabled` flag come from context.tf (cloudposse/label/null).
# Resource names are built from namespace/tenant/environment/stage/name/attributes,
# e.g. namespace = "eg", stage = "prod", name = "shortener" -> "eg-prod-shortener-api".

variable "org_id" {
  type        = string
  description = "AWS Organization ID (e.g. `o-abc123defg`). Only principals in this organization may call the management API (`/api/*`)."

  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.org_id))
    error_message = "The org_id must be an AWS Organization ID such as o-abc123defg."
  }
}

variable "url_prefix" {
  type        = string
  default     = ""
  description = "Optional URL prefix used when formatting short URLs returned by the API (e.g. `https://sho.rt`). Equivalent to the SAM `CustomDomainName` parameter."

  validation {
    condition     = var.url_prefix == "" || can(regex("^https?://[^/]+$", var.url_prefix))
    error_message = "The url_prefix must be empty or a scheme and host without a trailing slash, e.g. https://sho.rt."
  }
}

variable "default_link_ttl_seconds" {
  type        = number
  default     = 31536000
  description = "Default lifetime of a link in seconds when the create request has no `ttl`. Equivalent to the SAM `TTL` parameter."

  validation {
    condition     = var.default_link_ttl_seconds >= 1 && floor(var.default_link_ttl_seconds) == var.default_link_ttl_seconds
    error_message = "The default_link_ttl_seconds must be a positive whole number."
  }
}

variable "domain_alias" {
  type        = string
  default     = ""
  description = "Optional custom hostname served by CloudFront (e.g. `go.example.com`). Requires `acm_certificate_arn`. Equivalent to the SAM `DomainAlias` parameter."

  validation {
    condition     = var.domain_alias == "" || can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$", var.domain_alias))
    error_message = "The domain_alias must be a lowercase hostname without scheme or path, e.g. go.example.com."
  }
}

variable "acm_certificate_arn" {
  type        = string
  default     = ""
  description = "ARN of an ACM certificate in `us-east-1` covering `domain_alias` (CloudFront only accepts certificates from us-east-1). Required when `domain_alias` is set."

  validation {
    condition     = var.acm_certificate_arn == "" || can(regex("^arn:aws[a-z-]*:acm:us-east-1:[0-9]{12}:certificate/[0-9a-f-]+$", var.acm_certificate_arn))
    error_message = "The acm_certificate_arn must be an ACM certificate ARN in us-east-1."
  }
}

variable "hosted_zone_id" {
  type        = string
  default     = ""
  description = "Optional Route 53 hosted zone ID for `domain_alias`. When set, alias A and AAAA records pointing to CloudFront are created."
}

variable "alarm_email" {
  type        = string
  default     = ""
  description = "Optional email address subscribed to both alarm topics (regional and us-east-1). Confirm the SNS subscription emails after apply."
}

variable "enable_dashboard" {
  type        = bool
  default     = true
  description = "Create a CloudWatch dashboard for link traffic and service health (the first 3 dashboards per account are free)."
}

variable "enable_cloudfront_additional_metrics" {
  type        = bool
  default     = false
  description = "Enable CloudFront additional metrics (billed as CloudWatch custom metrics) and the CacheHitRate alarm that needs them."
}

variable "api_4xx_error_rate_threshold" {
  type        = number
  default     = 0.01
  description = "API Gateway 4xx error rate (0-1, Average of 4XXError over 1 minute) above which the 4xx alarm fires. Default matches the SAM template."

  validation {
    condition     = var.api_4xx_error_rate_threshold >= 0 && var.api_4xx_error_rate_threshold <= 1
    error_message = "The api_4xx_error_rate_threshold must be between 0 and 1."
  }
}

variable "api_5xx_error_rate_threshold" {
  type        = number
  default     = 0.01
  description = "API Gateway 5xx error rate (0-1, Average of 5XXError over 1 minute) above which the 5xx alarm fires."

  validation {
    condition     = var.api_5xx_error_rate_threshold >= 0 && var.api_5xx_error_rate_threshold <= 1
    error_message = "The api_5xx_error_rate_threshold must be between 0 and 1."
  }
}

variable "api_latency_p99_threshold_ms" {
  type        = number
  default     = 75
  description = "API Gateway p99 latency in milliseconds (5 minute period) above which the latency alarm fires."
}

variable "dynamodb_system_errors_threshold" {
  type        = number
  default     = 1
  description = "DynamoDB SystemErrors per minute at or above which a datapoint breaches (alarm on 2 of 5 minutes)."
}

variable "cloudfront_error_rate_threshold" {
  type        = number
  default     = 5
  description = "CloudFront TotalErrorRate percentage (5 minute average) above which the CloudFront error alarm fires."
}

variable "cloudfront_cache_hit_rate_threshold" {
  type        = number
  default     = 80
  description = "CloudFront CacheHitRate percentage at or below which (for 15 minutes) the cache hit alarm fires. Only used with enable_cloudfront_additional_metrics."
}
