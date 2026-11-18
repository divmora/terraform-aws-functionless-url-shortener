variable "region" {
  type        = string
  description = "AWS region for the API, table and regional alarms"
}

variable "org_id" {
  type        = string
  description = "AWS Organization ID allowed to call the management API"
}

variable "domain_alias" {
  type        = string
  default     = ""
  description = "Optional custom hostname served by CloudFront (e.g. go.example.com)"
}

variable "acm_certificate_arn" {
  type        = string
  default     = ""
  description = "ACM certificate ARN in us-east-1 covering domain_alias"
}

variable "hosted_zone_id" {
  type        = string
  default     = ""
  description = "Optional Route 53 hosted zone ID; creates A/AAAA alias records for domain_alias"
}

variable "url_prefix" {
  type        = string
  default     = ""
  description = "Optional URL prefix for returned short URLs (e.g. https://sho.rt)"
}
