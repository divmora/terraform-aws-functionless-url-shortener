# Unit tests with mocked AWS providers (no AWS access needed).
# mock_provider requires Terraform >= 1.7 / OpenTofu >= 1.8; CI runs these on latest only.

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      name = "ap-south-1"
    }
  }
}

mock_provider "aws" {
  alias = "us_east_1"
}

variables {
  org_id = "o-abc123defg"
}

run "defaults" {
  command = apply

  assert {
    condition     = aws_api_gateway_rest_api.this.name == "url-shortener-api"
    error_message = "REST API must be named <name>-api so alarms can filter on ApiName."
  }

  assert {
    condition     = aws_dynamodb_table.links.name == "url-shortener-links"
    error_message = "Unexpected table name."
  }

  assert {
    condition     = aws_dynamodb_table.links.billing_mode == "PAY_PER_REQUEST" && aws_dynamodb_table.links.hash_key == "id"
    error_message = "Table must be on-demand with hash key id."
  }

  assert {
    condition     = one(aws_dynamodb_table.links.ttl).attribute_name == "ttl" && one(aws_dynamodb_table.links.ttl).enabled
    error_message = "TTL must be enabled on the ttl attribute."
  }

  assert {
    condition     = one(aws_dynamodb_table.links.global_secondary_index).name == "OwnerIndex"
    error_message = "OwnerIndex GSI is required."
  }

  assert {
    condition     = strcontains(local.api_body, "title: url-shortener-api")
    error_message = "OpenAPI info.title must match the API name."
  }

  assert {
    condition     = strcontains(local.api_body, "arn:aws:apigateway:ap-south-1:dynamodb:action/GetItem")
    error_message = "Integration URIs must use the current region."
  }

  assert {
    condition     = strcontains(local.api_body, "#set($ttl = 31536000)")
    error_message = "Default TTL must be rendered into the create mapping template."
  }

  assert {
    condition     = strcontains(local.api_body, "\"shortUrl\":\"/?go=$inputRoot")
    error_message = "With no url_prefix the short URL prefix must be empty (SAM parity)."
  }

  assert {
    condition     = !strcontains(local.api_body, "$${") && !strcontains(local.api_body, "Fn::")
    error_message = "Rendered body must not contain unrendered placeholders or CloudFormation intrinsics."
  }

  assert {
    condition     = aws_api_gateway_stage.prod.stage_name == "Prod" && aws_api_gateway_stage.prod.xray_tracing_enabled
    error_message = "Stage must be Prod with X-Ray tracing (SAM parity)."
  }

  assert {
    condition = (
      one(aws_api_gateway_method_settings.all.settings).logging_level == "INFO" &&
      one(aws_api_gateway_method_settings.all.settings).data_trace_enabled &&
      one(aws_api_gateway_method_settings.all.settings).metrics_enabled &&
      one(aws_api_gateway_method_settings.all.settings).throttling_rate_limit == 2000 &&
      one(aws_api_gateway_method_settings.all.settings).throttling_burst_limit == 1000
    )
    error_message = "*/* method settings must match SAM."
  }

  assert {
    condition = (
      aws_api_gateway_method_settings.redirect.method_path == "{linkId}/GET" &&
      one(aws_api_gateway_method_settings.redirect.settings).throttling_rate_limit == 10000 &&
      one(aws_api_gateway_method_settings.redirect.settings).throttling_burst_limit == 4000
    )
    error_message = "GET /{linkId} throttling must match SAM."
  }

  assert {
    condition     = one(aws_cloudfront_distribution.this.origin).origin_path == "/Prod"
    error_message = "CloudFront must forward to the Prod stage."
  }

  assert {
    condition     = one(one(aws_cloudfront_distribution.this.default_cache_behavior).forwarded_values).query_string_cache_keys == tolist(["go"])
    error_message = "Only the go query string may be part of the cache key."
  }

  assert {
    condition     = output.short_url_base == "https://${aws_cloudfront_distribution.this.domain_name}"
    error_message = "short_url_base must fall back to the CloudFront domain."
  }
}

run "url_prefix" {
  command = apply

  variables {
    url_prefix = "https://sho.rt"
  }

  assert {
    condition     = strcontains(local.api_body, "\"shortUrl\":\"https://sho.rt/?go=$inputRoot")
    error_message = "url_prefix must be used in returned short URLs."
  }

  assert {
    condition     = output.short_url_base == "https://sho.rt"
    error_message = "short_url_base must use url_prefix."
  }
}

run "custom_name_and_ttl" {
  command = apply

  variables {
    name                     = "go-links"
    default_link_ttl_seconds = 604800
  }

  assert {
    condition     = aws_api_gateway_rest_api.this.name == "go-links-api" && aws_iam_role.ddb_read.name == "go-links-ddb-read"
    error_message = "Names must follow var.name."
  }

  assert {
    condition     = strcontains(local.api_body, "#set($ttl = 604800)")
    error_message = "Custom default TTL must be rendered."
  }
}

run "rejects_invalid_org_id" {
  command = plan

  variables {
    org_id = "123456789012"
  }

  expect_failures = [var.org_id]
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Bad_Name"
  }

  expect_failures = [var.name]
}

run "rejects_url_prefix_with_trailing_slash" {
  command = plan

  variables {
    url_prefix = "https://sho.rt/"
  }

  expect_failures = [var.url_prefix]
}
