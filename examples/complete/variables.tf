variable "region" {
  type        = string
  description = "AWS region for the API, table and regional alarms"
}

variable "org_id" {
  type        = string
  description = "AWS Organization ID allowed to call the management API"
}

variable "url_prefix" {
  type        = string
  default     = ""
  description = "Optional URL prefix for returned short URLs (e.g. https://sho.rt)"
}
