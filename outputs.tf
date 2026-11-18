output "management_api_endpoint" {
  description = "SigV4 management API endpoint (execute-api stage URL). Call this directly, not via CloudFront; pass it to `shorten --endpoint`."
  value       = one(aws_api_gateway_stage.prod[*].invoke_url)
}

output "api_id" {
  description = "ID of the API Gateway REST API."
  value       = one(aws_api_gateway_rest_api.this[*].id)
}

output "api_name" {
  description = "Name of the REST API (the `ApiName` CloudWatch dimension)."
  value       = one(aws_api_gateway_rest_api.this[*].name)
}

output "cloudfront_domain_name" {
  description = "CloudFront domain serving public redirects (SAM output `AppAPIRoot`)."
  value       = one(aws_cloudfront_distribution.this[*].domain_name)
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID."
  value       = one(aws_cloudfront_distribution.this[*].id)
}

output "short_url_base" {
  description = "Base URL for short links: `url_prefix` if set, else `https://<domain_alias>`, else the CloudFront domain."
  value       = local.enabled ? (local.short_url_prefix != "" ? local.short_url_prefix : "https://${one(aws_cloudfront_distribution.this[*].domain_name)}") : null
}

output "dns_target" {
  description = "When `domain_alias` is set without `hosted_zone_id`, point a CNAME for the alias at this CloudFront domain."
  value       = local.enabled && local.has_domain_alias ? one(aws_cloudfront_distribution.this[*].domain_name) : null
}

output "dns_record_fqdns" {
  description = "FQDNs of the Route 53 alias records created for `domain_alias` (empty unless `hosted_zone_id` is set)."
  value       = concat(aws_route53_record.a[*].fqdn, aws_route53_record.aaaa[*].fqdn)
}

output "table_name" {
  description = "Name of the DynamoDB link table."
  value       = one(aws_dynamodb_table.links[*].name)
}

output "table_arn" {
  description = "ARN of the DynamoDB link table."
  value       = one(aws_dynamodb_table.links[*].arn)
}
