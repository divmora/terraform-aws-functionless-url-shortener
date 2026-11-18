# Unit tests with mocked AWS providers (no AWS access needed).
# mock_provider requires Terraform >= 1.7 / OpenTofu >= 1.8; CI runs these on latest only.

mock_provider "aws" {
  mock_resource "aws_dynamodb_table" {
    defaults = {
      arn = "arn:aws:dynamodb:ap-south-1:123456789012:table/eg-test-shortener-links"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

mock_provider "aws" {
  alias = "us_east_1"
}

variables {
  namespace = "eg"
  stage     = "test"
  name      = "shortener"
  org_id    = "o-abc123defg"
}

run "defaults" {
  command = apply

  assert {
    condition     = aws_api_gateway_rest_api.this[0].name == "eg-test-shortener-api"
    error_message = "REST API must be named <id>-api (it is the ApiName alarm dimension)."
  }

  assert {
    condition     = aws_dynamodb_table.links[0].name == "eg-test-shortener-links"
    error_message = "Unexpected table name."
  }

  assert {
    condition     = aws_iam_role.ddb_read[0].name == "eg-test-shortener-ddb-read" && aws_iam_role.ddb_crud[0].name == "eg-test-shortener-ddb-crud"
    error_message = "Role names must follow the label."
  }

  assert {
    condition     = aws_dynamodb_table.links[0].tags["Namespace"] == "eg" && aws_dynamodb_table.links[0].tags["Stage"] == "test" && aws_dynamodb_table.links[0].tags["Name"] == "eg-test-shortener-links"
    error_message = "Resources must carry the null-label tags."
  }

  assert {
    condition     = aws_dynamodb_table.links[0].billing_mode == "PAY_PER_REQUEST" && aws_dynamodb_table.links[0].hash_key == "id"
    error_message = "Table must be on-demand with hash key id."
  }

  assert {
    condition     = one(aws_dynamodb_table.links[0].ttl).attribute_name == "ttl" && one(aws_dynamodb_table.links[0].ttl).enabled
    error_message = "TTL must be enabled on the ttl attribute."
  }

  assert {
    condition     = one(aws_dynamodb_table.links[0].global_secondary_index).name == "OwnerIndex"
    error_message = "OwnerIndex GSI is required."
  }

  assert {
    condition     = strcontains(local.api_body, "title: eg-test-shortener-api")
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
    condition     = aws_api_gateway_stage.prod[0].stage_name == "Prod" && aws_api_gateway_stage.prod[0].xray_tracing_enabled
    error_message = "Stage must be Prod with X-Ray tracing (SAM parity)."
  }

  assert {
    condition = (
      one(aws_api_gateway_method_settings.all[0].settings).logging_level == "INFO" &&
      one(aws_api_gateway_method_settings.all[0].settings).data_trace_enabled &&
      one(aws_api_gateway_method_settings.all[0].settings).metrics_enabled &&
      one(aws_api_gateway_method_settings.all[0].settings).throttling_rate_limit == 2000 &&
      one(aws_api_gateway_method_settings.all[0].settings).throttling_burst_limit == 1000
    )
    error_message = "*/* method settings must match SAM."
  }

  assert {
    condition = (
      aws_api_gateway_method_settings.redirect[0].method_path == "{linkId}/GET" &&
      one(aws_api_gateway_method_settings.redirect[0].settings).throttling_rate_limit == 10000 &&
      one(aws_api_gateway_method_settings.redirect[0].settings).throttling_burst_limit == 4000
    )
    error_message = "GET /{linkId} throttling must match SAM."
  }

  assert {
    condition     = one(aws_cloudfront_distribution.this[0].origin).origin_path == "/Prod"
    error_message = "CloudFront must forward to the Prod stage."
  }

  assert {
    condition     = one(one(aws_cloudfront_distribution.this[0].default_cache_behavior).forwarded_values).query_string_cache_keys == tolist(["go"])
    error_message = "Only the go query string may be part of the cache key."
  }

  assert {
    condition     = output.short_url_base == "https://${aws_cloudfront_distribution.this[0].domain_name}"
    error_message = "short_url_base must fall back to the CloudFront domain."
  }
}

run "disabled" {
  command = apply

  variables {
    enabled = false
  }

  assert {
    condition = (
      length(aws_dynamodb_table.links) == 0 &&
      length(aws_iam_role.ddb_read) == 0 &&
      length(aws_iam_role.ddb_crud) == 0 &&
      length(aws_api_gateway_rest_api.this) == 0 &&
      length(aws_api_gateway_stage.prod) == 0 &&
      length(aws_cloudfront_distribution.this) == 0
    )
    error_message = "enabled = false must create no resources."
  }

  assert {
    condition     = output.management_api_endpoint == null && output.short_url_base == null && output.table_name == null
    error_message = "Outputs must be null when disabled."
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

run "attributes_and_ttl" {
  command = apply

  variables {
    environment              = "aps1"
    attributes               = ["blue"]
    default_link_ttl_seconds = 604800
  }

  assert {
    condition     = aws_api_gateway_rest_api.this[0].name == "eg-aps1-test-shortener-blue-api"
    error_message = "Names must include environment and attributes from the context."
  }

  assert {
    condition     = strcontains(local.api_body, "#set($ttl = 604800)")
    error_message = "Custom default TTL must be rendered."
  }
}

run "long_names_fit_iam_limit" {
  command = apply

  variables {
    namespace = "averyveryverylongnamespace"
    name      = "averyveryverylongapplicationname"
  }

  assert {
    condition     = length(aws_iam_role.ddb_read[0].name) <= 64 && length(aws_iam_role.ddb_crud[0].name) <= 64
    error_message = "IAM role names must be truncated to 64 characters."
  }
}

run "requires_a_label" {
  command = plan

  variables {
    namespace = null
    stage     = null
    name      = null
  }

  expect_failures = [aws_dynamodb_table.links]
}

run "rejects_invalid_org_id" {
  command = plan

  variables {
    org_id = "123456789012"
  }

  expect_failures = [var.org_id]
}

run "rejects_url_prefix_with_trailing_slash" {
  command = plan

  variables {
    url_prefix = "https://sho.rt/"
  }

  expect_failures = [var.url_prefix]
}
