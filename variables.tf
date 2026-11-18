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
