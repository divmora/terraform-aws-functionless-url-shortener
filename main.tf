data "aws_region" "current" {}

locals {
  api_name = "${var.name}-api"
  region   = data.aws_region.current.name

  # Mirrors the SAM Fn::If chain for shortUrlPrefix (custom domain fallback added in M2).
  short_url_prefix = var.url_prefix
}

##   DynamoDB link table
resource "aws_dynamodb_table" "links" {
  name         = "${var.name}-links"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "owner"
    type = "S"
  }

  global_secondary_index {
    name            = "OwnerIndex"
    hash_key        = "owner"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = var.tags
}
