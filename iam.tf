##   Roles assumed by API Gateway for its direct DynamoDB integrations (no Lambda).

data "aws_iam_policy_document" "apigateway_assume" {
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
  name               = "${var.name}-ddb-read"
  assume_role_policy = data.aws_iam_policy_document.apigateway_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "ddb_read" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:Scan",
      "dynamodb:Query",
    ]
    resources = [
      aws_dynamodb_table.links.arn,
      "${aws_dynamodb_table.links.arn}/index/*",
    ]
  }
}

resource "aws_iam_role_policy" "ddb_read" {
  name   = "DDBReadPolicy"
  role   = aws_iam_role.ddb_read.id
  policy = data.aws_iam_policy_document.ddb_read.json
}

##   Read/write role: UpdateItem for POST /api, DeleteItem for DELETE /api/{linkId}
resource "aws_iam_role" "ddb_crud" {
  name               = "${var.name}-ddb-crud"
  assume_role_policy = data.aws_iam_policy_document.apigateway_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "ddb_crud" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:DeleteItem",
      "dynamodb:UpdateItem",
    ]
    resources = [aws_dynamodb_table.links.arn]
  }
}

resource "aws_iam_role_policy" "ddb_crud" {
  name   = "DDBCrudPolicy"
  role   = aws_iam_role.ddb_crud.id
  policy = data.aws_iam_policy_document.ddb_crud.json
}
