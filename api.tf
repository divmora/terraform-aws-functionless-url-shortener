##   REST API defined by the shared OpenAPI/VTL template (see scripts/render_api_template.py).

locals {
  # try(..., "") keeps templatefile() happy when enabled = false (no resources exist).
  api_body = templatefile("${path.module}/templates/api.yaml.tftpl", {
    api_name                 = module.api_label.id
    region                   = local.region
    table_name               = try(aws_dynamodb_table.links[0].name, "")
    read_role_arn            = try(aws_iam_role.ddb_read[0].arn, "")
    crud_role_arn            = try(aws_iam_role.ddb_crud[0].arn, "")
    default_link_ttl_seconds = var.default_link_ttl_seconds
    short_url_prefix         = local.short_url_prefix
  })
}

resource "aws_api_gateway_rest_api" "this" {
  count = local.enabled ? 1 : 0

  name = module.api_label.id
  body = local.api_body

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = module.api_label.tags
}

##   Same statements as the SAM Auth.ResourcePolicy: public GET (redirects), and /api/* only
##   for principals inside the AWS Organization. Full execution ARNs are used instead of the
##   execute-api:/ shorthand, which API Gateway expands on save (causing a perpetual diff).
data "aws_iam_policy_document" "api_resource_policy" {
  count = local.enabled ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["execute-api:Invoke"]
    resources = ["${aws_api_gateway_rest_api.this[0].execution_arn}/*/GET/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }

  statement {
    effect    = "Deny"
    actions   = ["execute-api:Invoke"]
    resources = ["${aws_api_gateway_rest_api.this[0].execution_arn}/*/*/api/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "StringNotEquals"
      variable = "aws:PrincipalOrgID"
      values   = [var.org_id]
    }
  }

  statement {
    effect    = "Allow"
    actions   = ["execute-api:Invoke"]
    resources = ["${aws_api_gateway_rest_api.this[0].execution_arn}/*/*/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [var.org_id]
    }
  }
}

resource "aws_api_gateway_rest_api_policy" "this" {
  count = local.enabled ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.this[0].id
  policy      = data.aws_iam_policy_document.api_resource_policy[0].json
}

##   SAM creates the deployment and stage implicitly; here a new deployment is created whenever
##   the API body or resource policy changes, before the old one is removed.
resource "aws_api_gateway_deployment" "this" {
  count = local.enabled ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.this[0].id

  triggers = {
    redeployment = sha1(jsonencode([
      local.api_body,
      data.aws_iam_policy_document.api_resource_policy[0].json,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_api_gateway_rest_api_policy.this]
}

resource "aws_api_gateway_stage" "prod" {
  count = local.enabled ? 1 : 0

  rest_api_id          = aws_api_gateway_rest_api.this[0].id
  deployment_id        = aws_api_gateway_deployment.this[0].id
  stage_name           = "Prod"
  xray_tracing_enabled = true
  tags                 = module.api_label.tags
}

##   Copied as-is from the SAM MethodSettings (decision: keep API logging identical).
##   INFO execution logging requires the account-level API Gateway CloudWatch Logs role
##   (aws_api_gateway_account); see README.
resource "aws_api_gateway_method_settings" "all" {
  count = local.enabled ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.this[0].id
  stage_name  = aws_api_gateway_stage.prod[0].stage_name
  method_path = "*/*"

  settings {
    logging_level          = "INFO"
    data_trace_enabled     = true
    metrics_enabled        = true
    throttling_rate_limit  = 2000
    throttling_burst_limit = 1000
  }
}

resource "aws_api_gateway_method_settings" "redirect" {
  count = local.enabled ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.this[0].id
  stage_name  = aws_api_gateway_stage.prod[0].stage_name
  method_path = "{linkId}/GET"

  # Matches what SAM deploys for this path (verified against a live SAM stack): execution
  # logging off, metrics and data trace flags on, higher throttling for redirects.
  settings {
    logging_level          = "OFF"
    metrics_enabled        = true
    data_trace_enabled     = true
    throttling_rate_limit  = 10000
    throttling_burst_limit = 4000
  }
}
