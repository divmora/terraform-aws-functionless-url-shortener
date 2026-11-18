terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# CloudFront metrics exist only in us-east-1; the module creates CloudFront alarms there.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

variable "region" {
  description = "Region for the API, table and regional alarms."
  type        = string
  default     = "ap-south-1"
}

variable "org_id" {
  description = "AWS Organization ID allowed to call the management API."
  type        = string
}

module "url_shortener" {
  source = "../.."

  name   = "url-shortener"
  org_id = var.org_id

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}

output "management_api_endpoint" {
  description = "Pass to: shorten --endpoint <value>"
  value       = module.url_shortener.management_api_endpoint
}

output "short_url_base" {
  description = "Base URL for short links."
  value       = module.url_shortener.short_url_base
}
