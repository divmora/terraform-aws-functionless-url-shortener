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

  name   = "url-shortener"
  org_id = "o-xxxxxxxxxx"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}
```

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
