terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
      # CloudFront metrics exist only in us-east-1, so CloudFront alarms and their SNS topic
      # are created through this aliased provider.
      configuration_aliases = [aws.us_east_1]
    }
  }
}
