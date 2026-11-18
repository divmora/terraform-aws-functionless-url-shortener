output "management_api_endpoint" {
  description = "Management API endpoint; pass to `shorten --endpoint`"
  value       = module.url_shortener.management_api_endpoint
}

output "api_name" {
  description = "Name of the REST API"
  value       = module.url_shortener.api_name
}

output "cloudfront_domain_name" {
  description = "CloudFront domain serving public redirects"
  value       = module.url_shortener.cloudfront_domain_name
}

output "short_url_base" {
  description = "Base URL for short links"
  value       = module.url_shortener.short_url_base
}

output "dns_target" {
  description = "CNAME target for domain_alias when no hosted zone is given"
  value       = module.url_shortener.dns_target
}

output "table_name" {
  description = "Name of the DynamoDB link table"
  value       = module.url_shortener.table_name
}
