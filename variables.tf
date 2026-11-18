variable "name" {
  description = "Name prefix for all resources (replaces the CloudFormation stack name). The REST API is named \"<name>-api\"."
  type        = string
  default     = "url-shortener"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.name))
    error_message = "name must be 2-40 characters of lowercase letters, digits and hyphens, start with a letter and not end with a hyphen."
  }
}

variable "org_id" {
  description = "AWS Organization ID (e.g. o-abc123defg). Only principals in this organization may call the management API (/api/*)."
  type        = string

  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.org_id))
    error_message = "org_id must be an AWS Organization ID such as o-abc123defg."
  }
}

variable "url_prefix" {
  description = "Optional URL prefix used when formatting short URLs returned by the API (e.g. https://sho.rt). Equivalent to the SAM CustomDomainName parameter."
  type        = string
  default     = ""

  validation {
    condition     = var.url_prefix == "" || can(regex("^https?://[^/]+$", var.url_prefix))
    error_message = "url_prefix must be empty or a scheme and host without a trailing slash, e.g. https://sho.rt."
  }
}

variable "default_link_ttl_seconds" {
  description = "Default lifetime of a link in seconds when the create request has no ttl. Equivalent to the SAM TTL parameter."
  type        = number
  default     = 31536000

  validation {
    condition     = var.default_link_ttl_seconds >= 1 && floor(var.default_link_ttl_seconds) == var.default_link_ttl_seconds
    error_message = "default_link_ttl_seconds must be a positive whole number."
  }
}

variable "tags" {
  description = "Tags applied to all taggable resources."
  type        = map(string)
  default     = {}
}
