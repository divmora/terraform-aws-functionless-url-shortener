##   REST API defined by the shared OpenAPI/VTL template (see scripts/render_api_template.py).

locals {
  api_body = templatefile("${path.module}/templates/api.yaml.tftpl", {
    api_name                 = local.api_name
    region                   = local.region
    table_name               = aws_dynamodb_table.links.name
    read_role_arn            = aws_iam_role.ddb_read.arn
    crud_role_arn            = aws_iam_role.ddb_crud.arn
    default_link_ttl_seconds = var.default_link_ttl_seconds
    short_url_prefix         = local.short_url_prefix
  })
}

resource "aws_api_gateway_rest_api" "this" {
  name = local.api_name
  body = local.api_body

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = var.tags
}

##   Same statements as the SAM Auth.ResourcePolicy: public GET (redirects), and /api/* only
##   for principals inside the AWS Organization.
data "aws_iam_policy_document" "api_resource_policy" {
  statement {
    effect    = "Allow"
    actions   = ["execute-api:Invoke"]
    resources = ["execute-api:/*/GET/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }

  statement {
    effect    = "Deny"
    actions   = ["execute-api:Invoke"]
    resources = ["execute-api:/*/*/api/*"]

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
    resources = ["execute-api:/*/*/*"]

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
  rest_api_id = aws_api_gateway_rest_api.this.id
  policy      = data.aws_iam_policy_document.api_resource_policy.json
}

##   SAM creates the deployment and stage implicitly; here a new deployment is created whenever
##   the API body or resource policy changes, before the old one is removed.
resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeployment = sha1(jsonencode([
      local.api_body,
      data.aws_iam_policy_document.api_resource_policy.json,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_api_gateway_rest_api_policy.this]
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id          = aws_api_gateway_rest_api.this.id
  deployment_id        = aws_api_gateway_deployment.this.id
  stage_name           = "Prod"
  xray_tracing_enabled = true
  tags                 = var.tags
}

##   Copied as-is from the SAM MethodSettings (decision: keep API logging identical).
##   INFO execution logging requires the account-level API Gateway CloudWatch Logs role
##   (aws_api_gateway_account); see README.
resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
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
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  method_path = "{linkId}/GET"

  settings {
    throttling_rate_limit  = 10000
    throttling_burst_limit = 4000
  }
}
