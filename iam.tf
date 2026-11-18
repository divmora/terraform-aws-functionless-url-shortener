##   Roles assumed by API Gateway for its direct DynamoDB integrations (no Lambda).

data "aws_iam_policy_document" "apigateway_assume" {
  count = local.enabled ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

##   Read role: GetItem for redirects and GET /api/{linkId}
resource "aws_iam_role" "ddb_read" {
  count = local.enabled ? 1 : 0

  name               = module.ddb_read_role_label.id
  assume_role_policy = data.aws_iam_policy_document.apigateway_assume[0].json
  tags               = module.ddb_read_role_label.tags
}

data "aws_iam_policy_document" "ddb_read" {
  count = local.enabled ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:Scan",
      "dynamodb:Query",
    ]
    resources = [
      aws_dynamodb_table.links[0].arn,
      "${aws_dynamodb_table.links[0].arn}/index/*",
    ]
  }
}

resource "aws_iam_role_policy" "ddb_read" {
  count = local.enabled ? 1 : 0

  name   = "DDBReadPolicy"
  role   = aws_iam_role.ddb_read[0].id
  policy = data.aws_iam_policy_document.ddb_read[0].json
}

##   Read/write role: UpdateItem for POST /api, DeleteItem for DELETE /api/{linkId}
resource "aws_iam_role" "ddb_crud" {
  count = local.enabled ? 1 : 0

  name               = module.ddb_crud_role_label.id
  assume_role_policy = data.aws_iam_policy_document.apigateway_assume[0].json
  tags               = module.ddb_crud_role_label.tags
}

data "aws_iam_policy_document" "ddb_crud" {
  count = local.enabled ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "dynamodb:DeleteItem",
      "dynamodb:UpdateItem",
    ]
    resources = [aws_dynamodb_table.links[0].arn]
  }
}

resource "aws_iam_role_policy" "ddb_crud" {
  count = local.enabled ? 1 : 0

  name   = "DDBCrudPolicy"
  role   = aws_iam_role.ddb_crud[0].id
  policy = data.aws_iam_policy_document.ddb_crud[0].json
}
