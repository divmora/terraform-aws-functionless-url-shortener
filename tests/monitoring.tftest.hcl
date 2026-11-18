# Monitoring (M3) unit tests with mocked AWS providers.

mock_provider "aws" {
  mock_resource "aws_dynamodb_table" {
    defaults = {
      arn = "arn:aws:dynamodb:ap-south-1:123456789012:table/eg-test-shortener-links"
    }
  }

  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      id             = "E1EXAMPLE12345"
      domain_name    = "d111111abcdef8.cloudfront.net"
      hosted_zone_id = "Z2FDTNDATAQYW2"
    }
  }

  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:ap-south-1:123456789012:eg-test-shortener-alarms"
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

  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:123456789012:eg-test-shortener-cloudfront-alarms"
    }
  }
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
    condition     = aws_sns_topic.alarms[0].name == "eg-test-shortener-alarms" && aws_sns_topic.cloudfront_alarms[0].name == "eg-test-shortener-cloudfront-alarms"
    error_message = "SNS topics must follow the label."
  }

  assert {
    condition     = length(aws_sns_topic_subscription.alarms_email) == 0 && length(aws_sns_topic_subscription.cloudfront_alarms_email) == 0
    error_message = "No email subscriptions without alarm_email."
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.api_4xx[0].alarm_name == "eg-test-shortener API 4xx" &&
      aws_cloudwatch_metric_alarm.api_4xx[0].dimensions == tomap({ ApiName = "eg-test-shortener-api", Stage = "Prod" }) &&
      aws_cloudwatch_metric_alarm.api_4xx[0].statistic == "Average" &&
      aws_cloudwatch_metric_alarm.api_4xx[0].threshold == 0.01 &&
      aws_cloudwatch_metric_alarm.api_4xx[0].period == 60 &&
      aws_cloudwatch_metric_alarm.api_4xx[0].treat_missing_data == "notBreaching"
    )
    error_message = "API 4xx alarm must match SAM (ApiName + Stage, Average > 1%, 1 min, missing = OK)."
  }

  assert {
    condition     = startswith(aws_cloudwatch_metric_alarm.api_4xx[0].alarm_description, "API Gateway 4xx error rate above 1% ")
    error_message = "Alarm description must show the threshold as a clean percentage."
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.api_5xx[0].metric_name == "5XXError" &&
      aws_cloudwatch_metric_alarm.api_5xx[0].threshold == 0.01
    )
    error_message = "API 5xx alarm must match SAM."
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.api_latency[0].extended_statistic == "p99" &&
      aws_cloudwatch_metric_alarm.api_latency[0].threshold == 75 &&
      aws_cloudwatch_metric_alarm.api_latency[0].period == 300
    )
    error_message = "API latency alarm must match SAM (p99 > 75 ms, 5 min)."
  }

  assert {
    condition = (
      length(aws_cloudwatch_metric_alarm.dynamodb_system_errors[0].metric_query) == 4 &&
      aws_cloudwatch_metric_alarm.dynamodb_system_errors[0].evaluation_periods == 5 &&
      aws_cloudwatch_metric_alarm.dynamodb_system_errors[0].datapoints_to_alarm == 2 &&
      aws_cloudwatch_metric_alarm.dynamodb_system_errors[0].comparison_operator == "GreaterThanOrEqualToThreshold"
    )
    error_message = "DynamoDB alarm must sum GetItem/UpdateItem/DeleteItem SystemErrors (2 of 5 minutes)."
  }

  assert {
    condition = alltrue([
      for q in aws_cloudwatch_metric_alarm.dynamodb_system_errors[0].metric_query :
      q.id == "total" || (
        one(q.metric).metric_name == "SystemErrors" &&
        one(q.metric).dimensions["TableName"] == "eg-test-shortener-links" &&
        contains(["GetItem", "UpdateItem", "DeleteItem"], one(q.metric).dimensions["Operation"])
      )
    ])
    error_message = "SystemErrors queries must use TableName + Operation (DynamoDB doesn't publish TableName alone)."
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.cloudfront_error_rate[0].metric_name == "TotalErrorRate" &&
      aws_cloudwatch_metric_alarm.cloudfront_error_rate[0].dimensions == tomap({ DistributionId = "E1EXAMPLE12345", Region = "Global" }) &&
      aws_cloudwatch_metric_alarm.cloudfront_error_rate[0].statistic == "Average" &&
      aws_cloudwatch_metric_alarm.cloudfront_error_rate[0].threshold == 5 &&
      aws_cloudwatch_metric_alarm.cloudfront_error_rate[0].alarm_actions == toset(["arn:aws:sns:us-east-1:123456789012:eg-test-shortener-cloudfront-alarms"])
    )
    error_message = "CloudFront error alarm must use Region=Global, Average > 5% and the us-east-1 topic."
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.cloudfront_cache_hit_rate) == 0 && length(aws_cloudfront_monitoring_subscription.this) == 0
    error_message = "Cache hit alarm and additional metrics are opt-in."
  }

  assert {
    condition     = aws_cloudwatch_dashboard.this[0].dashboard_name == "eg-test-shortener-traffic"
    error_message = "Dashboard must be created by default and follow the label."
  }

  assert {
    condition     = length(jsondecode(aws_cloudwatch_dashboard.this[0].dashboard_body).widgets) == 11
    error_message = "Dashboard must have the same 11 widgets as the SAM dashboard."
  }

  assert {
    condition     = length(jsondecode(aws_cloudwatch_dashboard.this[0].dashboard_body).widgets[10].properties.alarms) == 4
    error_message = "Alarm widget must list the 4 regional alarms."
  }

  assert {
    condition     = strcontains(output.dashboard_url, "region=ap-south-1#dashboards/dashboard/eg-test-shortener-traffic")
    error_message = "dashboard_url must point at the dashboard."
  }
}

run "email_and_additional_metrics" {
  command = apply

  variables {
    alarm_email                          = "ops@example.com"
    enable_cloudfront_additional_metrics = true
  }

  assert {
    condition = (
      aws_sns_topic_subscription.alarms_email[0].endpoint == "ops@example.com" &&
      aws_sns_topic_subscription.cloudfront_alarms_email[0].endpoint == "ops@example.com" &&
      aws_sns_topic_subscription.alarms_email[0].protocol == "email"
    )
    error_message = "alarm_email must subscribe to both topics."
  }

  assert {
    condition = (
      one(one(aws_cloudfront_monitoring_subscription.this[0].monitoring_subscription).realtime_metrics_subscription_config).realtime_metrics_subscription_status == "Enabled" &&
      aws_cloudwatch_metric_alarm.cloudfront_cache_hit_rate[0].metric_name == "CacheHitRate" &&
      aws_cloudwatch_metric_alarm.cloudfront_cache_hit_rate[0].threshold == 80 &&
      aws_cloudwatch_metric_alarm.cloudfront_cache_hit_rate[0].comparison_operator == "LessThanOrEqualToThreshold" &&
      aws_cloudwatch_metric_alarm.cloudfront_cache_hit_rate[0].evaluation_periods == 3
    )
    error_message = "Additional metrics must enable the monitoring subscription and CacheHitRate <= 80% for 15 minutes."
  }
}

run "custom_thresholds_and_no_dashboard" {
  command = apply

  variables {
    api_4xx_error_rate_threshold = 0.25
    api_latency_p99_threshold_ms = 200
    enable_dashboard             = false
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.api_4xx[0].threshold == 0.25 && aws_cloudwatch_metric_alarm.api_latency[0].threshold == 200
    error_message = "Thresholds must be configurable."
  }

  assert {
    condition     = length(aws_cloudwatch_dashboard.this) == 0 && output.dashboard_url == null
    error_message = "enable_dashboard = false must skip the dashboard."
  }
}

run "disabled_creates_no_monitoring" {
  command = apply

  variables {
    enabled                              = false
    alarm_email                          = "ops@example.com"
    enable_cloudfront_additional_metrics = true
  }

  assert {
    condition = (
      length(aws_sns_topic.alarms) == 0 && length(aws_sns_topic.cloudfront_alarms) == 0 &&
      length(aws_cloudwatch_metric_alarm.api_4xx) == 0 && length(aws_cloudwatch_metric_alarm.cloudfront_error_rate) == 0 &&
      length(aws_cloudfront_monitoring_subscription.this) == 0 && length(aws_cloudwatch_dashboard.this) == 0
    )
    error_message = "enabled = false must create no monitoring resources."
  }
}

run "rejects_error_rate_above_one" {
  command = plan

  variables {
    api_4xx_error_rate_threshold = 5
  }

  expect_failures = [var.api_4xx_error_rate_threshold]
}
