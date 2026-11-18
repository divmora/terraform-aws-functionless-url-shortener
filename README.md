# terraform-aws-functionless-url-shortener

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![CI](https://github.com/divmora/terraform-aws-functionless-url-shortener/actions/workflows/ci.yml/badge.svg)](https://github.com/divmora/terraform-aws-functionless-url-shortener/actions)

> [!WARNING]
> **Under active development, not yet usable.** This module is being ported from the [SAM/CloudFormation version](https://github.com/divmora/functionless-url-shortener) to reach feature parity. Track progress in the [milestone issues](https://github.com/divmora/terraform-aws-functionless-url-shortener/issues).

Terraform / OpenTofu module for the **Functionless URL Shortener**: a URL shortener on AWS with no Lambda and no containers. API Gateway VTL mapping templates talk directly to DynamoDB, the management API is restricted to your AWS Organization via IAM (SigV4), and CloudFront caches public redirects at the edge.

## Compatibility

| Tool | Supported versions |
| :--- | :--- |
| Terraform | `>= 1.6` |
| OpenTofu | `>= 1.6` |
| AWS provider | `hashicorp/aws >= 5.0` |

CI validates the module on the minimum and latest versions of both Terraform and OpenTofu. An [Atmos](https://atmos.tools) example will be provided.

## Planned usage

```hcl
provider "aws" {
  region = "ap-south-1"
}

# CloudFront metrics exist only in us-east-1; CloudFront alarms are created there.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "url_shortener" {
  source = "divmora/functionless-url-shortener/aws"
  # version = "x.x.x"

  namespace = "eg"
  stage     = "prod"
  name      = "shortener"

  org_id = "o-xxxxxxxxxx"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}
```

This module follows [Cloud Posse](https://github.com/cloudposse) conventions: naming, tagging and the `enabled` flag come from [`context.tf`](context.tf) ([cloudposse/label/null](https://github.com/cloudposse/terraform-null-label)). Pass `context = module.this.context` from a parent module, or set `namespace`, `tenant`, `environment`, `stage`, `name` and `attributes` directly. The example above creates resources such as `eg-prod-shortener-api` and `eg-prod-shortener-links`. Set `enabled = false` to create nothing.

See [`examples/complete`](examples/complete) for a full example.

### Custom domain

1. Request an ACM certificate for the hostname **in `us-east-1`** (CloudFront only accepts certificates from there) and wait until it is `ISSUED`.
2. Set the domain inputs:

   ```hcl
   module "url_shortener" {
     # ...
     domain_alias        = "go.example.com"
     acm_certificate_arn = "arn:aws:acm:us-east-1:111122223333:certificate/xxxx"
     hosted_zone_id      = "Z0123456789ABCDEFGHIJ" # optional: creates A/AAAA alias records
   }
   ```

3. Without `hosted_zone_id`, create a `CNAME` for the hostname pointing at the `dns_target` output.

Short URLs returned by the API then use `https://<domain_alias>` unless `url_prefix` is set. The domain can be added to an existing deployment later; the distribution is updated in place.

### Monitoring

| Alarm | Metric | Fires when (default) | Variable |
| :--- | :--- | :--- | :--- |
| `<id> API 4xx` / `API 5xx` | `AWS/ApiGateway` `4XXError` / `5XXError` (`ApiName=<id>-api`, `Stage=Prod`) | Error rate (Average) > 1% over 1 min | `api_4xx_error_rate_threshold`, `api_5xx_error_rate_threshold` |
| `<id> API Latency` | `AWS/ApiGateway` `Latency` | p99 > 75 ms over 5 min | `api_latency_p99_threshold_ms` |
| `<id> DynamoDB SystemErrors` | `AWS/DynamoDB` `SystemErrors` summed over `GetItem`, `UpdateItem`, `DeleteItem` | ≥ 1/min in 2 of 5 minutes | `dynamodb_system_errors_threshold` |
| `<id> CloudFront Error Rate` (us-east-1) | `AWS/CloudFront` `TotalErrorRate` (`Region=Global`) | Average > 5% over 5 min | `cloudfront_error_rate_threshold` |
| `<id> CloudFront Cache Hit Rate` (us-east-1, opt-in) | `AWS/CloudFront` `CacheHitRate` | Average ≤ 80% for 15 min | `cloudfront_cache_hit_rate_threshold` |

Defaults match the SAM template. CloudFront publishes metrics only in **us-east-1**, so its alarms and their SNS topic are created through the `aws.us_east_1` provider. Regional alarms notify `alarm_topic_arn`, CloudFront alarms notify `cloudfront_alarm_topic_arn`; set `alarm_email` to subscribe an address to both (confirm both emails). Missing data (no traffic) is treated as OK.

> [!TIP]
> The public redirect endpoints see bot and scanner traffic, and `/api` rejects unsigned calls with 403, so the 1% 4xx default can be noisy. Raise `api_4xx_error_rate_threshold` (e.g. `0.25`) for production.

`enable_cloudfront_additional_metrics = true` turns on CloudFront additional metrics (billed as CloudWatch custom metrics) and the cache hit alarm. `enable_dashboard` (default `true`) creates a CloudWatch dashboard; see the `dashboard_url` output.

### Prerequisite: API Gateway CloudWatch Logs role

The stage enables **INFO execution logging and data tracing** (same as the SAM version). API Gateway can only write those logs if the account has a CloudWatch Logs role configured in its API Gateway settings (once per account and region). If yours doesn't, set one up, for example:

```hcl
resource "aws_iam_role" "apigw_cloudwatch" {
  name = "api-gateway-cloudwatch-logs"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "apigateway.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "apigw_cloudwatch" {
  role       = aws_iam_role.apigw_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.apigw_cloudwatch.arn
}
```

> [!NOTE]
> Data tracing logs full request and response payloads to CloudWatch Logs.

Manage links with the [`shorten` CLI](https://github.com/divmora/functionless-url-shortener-cli) using `--endpoint` set to the module's `management_api_endpoint` output.

## Development

`templates/api.yaml.tftpl` is generated from the SAM repo's [`api.yaml`](https://github.com/divmora/functionless-url-shortener/blob/main/api.yaml) so both versions share the same API and VTL mapping templates. CI fails if they drift. To regenerate:

```bash
python3 scripts/render_api_template.py ../functionless-url-shortener/api.yaml
```

Run checks with Terraform and OpenTofu:

```bash
terraform fmt -recursive && terraform init -backend=false && terraform validate && terraform test
tofu fmt -recursive && tofu init -backend=false && tofu validate && tofu test
tflint --init && tflint --recursive
```

## License

[Apache License 2.0](LICENSE)
