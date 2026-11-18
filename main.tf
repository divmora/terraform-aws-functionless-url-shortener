locals {
  enabled = module.this.enabled

  # Region taken from the table ARN (arn:aws:dynamodb:<region>:...): works on AWS provider v5
  # and v6 without the deprecated aws_region.name attribute.
  # Empty when enabled = false.
  region = try(split(":", aws_dynamodb_table.links[0].arn)[3], "")

  has_domain_alias = var.domain_alias != ""
  create_dns       = local.enabled && local.has_domain_alias && var.hosted_zone_id != ""

  # Mirrors the SAM Fn::If chain for shortUrlPrefix: url_prefix, else https://<domain_alias>, else empty.
  short_url_prefix = var.url_prefix != "" ? var.url_prefix : (local.has_domain_alias ? "https://${var.domain_alias}" : "")
}

##   Labels (cloudposse/label/null), one per named resource
module "table_label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  attributes = ["links"]
  context    = module.this.context
}

module "api_label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  # The REST API name is the ApiName CloudWatch dimension used by the alarms.
  attributes = ["api"]
  context    = module.this.context
}

module "ddb_read_role_label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  attributes      = ["ddb", "read"]
  id_length_limit = 64 # IAM role name limit
  context         = module.this.context
}

module "ddb_crud_role_label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  attributes      = ["ddb", "crud"]
  id_length_limit = 64 # IAM role name limit
  context         = module.this.context
}

module "cdn_label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  attributes = ["cdn"]
  context    = module.this.context
}

##   DynamoDB link table
resource "aws_dynamodb_table" "links" {
  count = local.enabled ? 1 : 0

  name         = module.table_label.id
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

  tags = module.table_label.tags

  lifecycle {
    precondition {
      condition     = module.this.id != ""
      error_message = "Set at least one of namespace, tenant, environment, stage or name so resources get a name."
    }
  }
}
