##   Monitoring: SNS topics, CloudWatch alarms and dashboard. Mirrors the SAM template
##   (functionless-url-shortener#10 and #11). Every metric and dimension below was checked
##   against the AWS docs and a live deployment:
##   - API Gateway: ApiName + Stage; Average of 4XXError/5XXError is the error rate.
##   - DynamoDB SystemErrors is published only per TableName + Operation (not TableName alone).
##   - CloudFront metrics exist only in us-east-1 with Region = Global, so CloudFront alarms and
##     their SNS topic use the aws.us_east_1 provider.

locals {
  api_name = module.api_label.id

  create_cache_hit_alarm = local.enabled && var.enable_cloudfront_additional_metrics
}

module "alarms_label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  attributes = ["alarms"]
  context    = module.this.context
}

module "cloudfront_alarms_label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  attributes = ["cloudfront", "alarms"]
  context    = module.this.context
}

module "dashboard_label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  attributes = ["traffic"]
  context    = module.this.context
}

##   Regional SNS topic (API Gateway and DynamoDB alarms)
resource "aws_sns_topic" "alarms" {
  count = local.enabled ? 1 : 0

  name = module.alarms_label.id
  tags = module.alarms_label.tags
}

resource "aws_sns_topic_subscription" "alarms_email" {
  count = local.enabled && var.alarm_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

##   us-east-1 SNS topic (CloudFront alarms; alarm actions must be in the alarm's region)
resource "aws_sns_topic" "cloudfront_alarms" {
  count    = local.enabled ? 1 : 0
  provider = aws.us_east_1

  name = module.cloudfront_alarms_label.id
  tags = module.cloudfront_alarms_label.tags
}

resource "aws_sns_topic_subscription" "cloudfront_alarms_email" {
  count    = local.enabled && var.alarm_email != "" ? 1 : 0
  provider = aws.us_east_1

  topic_arn = aws_sns_topic.cloudfront_alarms[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

##   API Gateway alarms
resource "aws_cloudwatch_metric_alarm" "api_4xx" {
  count = local.enabled ? 1 : 0

  alarm_name          = "${module.this.id} API 4xx"
  alarm_description   = "API Gateway 4xx error rate above ${format("%.4g", var.api_4xx_error_rate_threshold * 100)}% (Average of 4XXError is the error rate)"
  namespace           = "AWS/ApiGateway"
  metric_name         = "4XXError"
  dimensions          = { ApiName = local.api_name, Stage = "Prod" }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 1
  threshold           = var.api_4xx_error_rate_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  tags                = module.alarms_label.tags
}

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  count = local.enabled ? 1 : 0

  alarm_name          = "${module.this.id} API 5xx"
  alarm_description   = "API Gateway 5xx error rate above ${format("%.4g", var.api_5xx_error_rate_threshold * 100)}% (Average of 5XXError is the error rate)"
  namespace           = "AWS/ApiGateway"
  metric_name         = "5XXError"
  dimensions          = { ApiName = local.api_name, Stage = "Prod" }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 1
  threshold           = var.api_5xx_error_rate_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  tags                = module.alarms_label.tags
}

resource "aws_cloudwatch_metric_alarm" "api_latency" {
  count = local.enabled ? 1 : 0

  alarm_name          = "${module.this.id} API Latency"
  alarm_description   = "API Gateway p99 latency above ${var.api_latency_p99_threshold_ms} ms"
  namespace           = "AWS/ApiGateway"
  metric_name         = "Latency"
  dimensions          = { ApiName = local.api_name, Stage = "Prod" }
  extended_statistic  = "p99"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.api_latency_p99_threshold_ms
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  tags                = module.alarms_label.tags
}

##   DynamoDB SystemErrors, summed over the operations the API uses (alarms can't use SEARCH()).
resource "aws_cloudwatch_metric_alarm" "dynamodb_system_errors" {
  count = local.enabled ? 1 : 0

  alarm_name          = "${module.this.id} DynamoDB SystemErrors"
  alarm_description   = "DynamoDB system (5xx) errors on the link table"
  evaluation_periods  = 5
  datapoints_to_alarm = 2
  threshold           = var.dynamodb_system_errors_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms[0].arn]
  tags                = module.alarms_label.tags

  metric_query {
    id          = "total"
    label       = "SystemErrors"
    expression  = "FILL(getitem, 0) + FILL(updateitem, 0) + FILL(deleteitem, 0)"
    return_data = true
  }

  dynamic "metric_query" {
    for_each = { getitem = "GetItem", updateitem = "UpdateItem", deleteitem = "DeleteItem" }

    content {
      id          = metric_query.key
      return_data = false

      metric {
        namespace   = "AWS/DynamoDB"
        metric_name = "SystemErrors"
        period      = 60
        stat        = "Sum"
        dimensions = {
          TableName = aws_dynamodb_table.links[0].name
          Operation = metric_query.value
        }
      }
    }
  }
}

##   CloudFront additional metrics (required for CacheHitRate; billed as CloudWatch custom metrics)
resource "aws_cloudfront_monitoring_subscription" "this" {
  count = local.create_cache_hit_alarm ? 1 : 0

  distribution_id = aws_cloudfront_distribution.this[0].id

  monitoring_subscription {
    realtime_metrics_subscription_config {
      realtime_metrics_subscription_status = "Enabled"
    }
  }
}

##   CloudFront alarms (us-east-1)
resource "aws_cloudwatch_metric_alarm" "cloudfront_error_rate" {
  count    = local.enabled ? 1 : 0
  provider = aws.us_east_1

  alarm_name          = "${module.this.id} CloudFront Error Rate"
  alarm_description   = "Percentage of viewer requests returning 4xx/5xx above ${var.cloudfront_error_rate_threshold}% for 5 minutes"
  namespace           = "AWS/CloudFront"
  metric_name         = "TotalErrorRate"
  dimensions          = { DistributionId = aws_cloudfront_distribution.this[0].id, Region = "Global" }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.cloudfront_error_rate_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.cloudfront_alarms[0].arn]
  tags                = module.cloudfront_alarms_label.tags
}

resource "aws_cloudwatch_metric_alarm" "cloudfront_cache_hit_rate" {
  count    = local.create_cache_hit_alarm ? 1 : 0
  provider = aws.us_east_1

  alarm_name          = "${module.this.id} CloudFront Cache Hit Rate"
  alarm_description   = "CloudFront cache hit rate at or below ${var.cloudfront_cache_hit_rate_threshold}% for 15 minutes"
  namespace           = "AWS/CloudFront"
  metric_name         = "CacheHitRate"
  dimensions          = { DistributionId = aws_cloudfront_distribution.this[0].id, Region = "Global" }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.cloudfront_cache_hit_rate_threshold
  comparison_operator = "LessThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.cloudfront_alarms[0].arn]
  tags                = module.cloudfront_alarms_label.tags

  depends_on = [aws_cloudfront_monitoring_subscription.this]
}

##   Dashboard (same widgets and layout as the SAM TrafficDashboard)
locals {
  dashboard_distribution = try(aws_cloudfront_distribution.this[0].id, "")
  dashboard_table        = try(aws_dynamodb_table.links[0].name, "")
  cf_dims                = ["DistributionId", local.dashboard_distribution, "Region", "Global"]
  api_dims               = ["ApiName", local.api_name]
  table_dims             = ["TableName", local.dashboard_table]

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "text", x = 0, y = 0, width = 24, height = 2
        properties = {
          markdown = "# ${module.this.id} — URL Shortener\nCloudFront metrics are global and shown from **us-east-1**; API Gateway and DynamoDB metrics are from **${local.region}**."
        }
      },
      {
        type = "metric", x = 0, y = 2, width = 8, height = 6
        properties = {
          title   = "CloudFront requests", view = "timeSeries", region = "us-east-1", stat = "Sum", period = 300
          metrics = [concat(["AWS/CloudFront", "Requests"], local.cf_dims)]
        }
      },
      {
        type = "metric", x = 8, y = 2, width = 8, height = 6
        properties = {
          title   = "CloudFront error rate (%)", view = "timeSeries", region = "us-east-1", stat = "Average", period = 300
          metrics = [for m in ["4xxErrorRate", "5xxErrorRate", "TotalErrorRate"] : concat(["AWS/CloudFront", m], local.cf_dims)]
        }
      },
      {
        type = "metric", x = 16, y = 2, width = 8, height = 6
        properties = {
          title   = "CloudFront cache hit rate (%) — requires additional metrics", view = "timeSeries", region = "us-east-1", stat = "Average", period = 300
          metrics = [concat(["AWS/CloudFront", "CacheHitRate"], local.cf_dims)]
          yAxis   = { left = { min = 0, max = 100 } }
        }
      },
      {
        type = "metric", x = 0, y = 8, width = 8, height = 6
        properties = {
          title   = "API Gateway requests", view = "timeSeries", region = local.region, stat = "Sum", period = 300
          metrics = [concat(["AWS/ApiGateway", "Count"], local.api_dims)]
        }
      },
      {
        type = "metric", x = 8, y = 8, width = 8, height = 6
        properties = {
          title = "API Gateway latency (ms)", view = "timeSeries", region = local.region, stat = "p99", period = 300
          metrics = [
            concat(["AWS/ApiGateway", "Latency"], local.api_dims, [{ stat = "p50", label = "Latency p50" }]),
            concat(["AWS/ApiGateway", "Latency"], local.api_dims, [{ stat = "p99", label = "Latency p99" }]),
            concat(["AWS/ApiGateway", "IntegrationLatency"], local.api_dims, [{ stat = "p99", label = "Integration p99" }]),
          ]
        }
      },
      {
        type = "metric", x = 16, y = 8, width = 8, height = 6
        properties = {
          title   = "API Gateway errors", view = "timeSeries", region = local.region, stat = "Sum", period = 300
          metrics = [for m in ["4XXError", "5XXError"] : concat(["AWS/ApiGateway", m], local.api_dims)]
        }
      },
      {
        type = "metric", x = 0, y = 14, width = 8, height = 6
        properties = {
          title   = "DynamoDB consumed capacity", view = "timeSeries", region = local.region, stat = "Sum", period = 300
          metrics = [for m in ["ConsumedReadCapacityUnits", "ConsumedWriteCapacityUnits"] : concat(["AWS/DynamoDB", m], local.table_dims)]
        }
      },
      {
        type = "metric", x = 8, y = 14, width = 8, height = 6
        properties = {
          title   = "DynamoDB throttles", view = "timeSeries", region = local.region, stat = "Sum", period = 300
          metrics = [for m in ["ReadThrottleEvents", "WriteThrottleEvents"] : concat(["AWS/DynamoDB", m], local.table_dims)]
        }
      },
      {
        type = "metric", x = 16, y = 14, width = 8, height = 6
        properties = {
          title = "DynamoDB system errors", view = "timeSeries", region = local.region, stat = "Sum", period = 300
          metrics = [[{
            expression = "SEARCH('{AWS/DynamoDB,Operation,TableName} MetricName=\"SystemErrors\" TableName=\"${local.dashboard_table}\"', 'Sum', 300)"
            id         = "e1"
            label      = "SystemErrors"
          }]]
        }
      },
      {
        type = "alarm", x = 0, y = 20, width = 24, height = 4
        properties = {
          title = "Alarm status"
          alarms = compact([
            try(aws_cloudwatch_metric_alarm.api_4xx[0].arn, ""),
            try(aws_cloudwatch_metric_alarm.api_5xx[0].arn, ""),
            try(aws_cloudwatch_metric_alarm.api_latency[0].arn, ""),
            try(aws_cloudwatch_metric_alarm.dynamodb_system_errors[0].arn, ""),
          ])
        }
      },
    ]
  })
}

resource "aws_cloudwatch_dashboard" "this" {
  count = local.enabled && var.enable_dashboard ? 1 : 0

  dashboard_name = module.dashboard_label.id
  dashboard_body = local.dashboard_body
}
