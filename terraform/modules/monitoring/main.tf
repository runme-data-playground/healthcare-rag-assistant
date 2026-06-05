variable "project_name" {}
variable "environment" {}
variable "alert_email" {}
variable "lambda_query_function_name" {}
variable "lambda_ingestion_function_name" {}
variable "api_gateway_id" {}
variable "aws_region" {}

data "aws_caller_identity" "current" {}

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-alerts"
  tags = { Name = "${var.project_name}-${var.environment}-alerts" }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_log_group" "lambda_query" {
  name              = "/aws/lambda/${var.lambda_query_function_name}"
  retention_in_days = 365
}

resource "aws_cloudwatch_log_group" "lambda_ingestion" {
  name              = "/aws/lambda/${var.lambda_ingestion_function_name}"
  retention_in_days = 365
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-query-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Query Lambda error rate elevated"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = { FunctionName = var.lambda_query_function_name }
}

resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${var.project_name}-${var.environment}-query-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "p95"
  threshold           = 25000
  alarm_description   = "Query Lambda p95 latency above 25s"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = { FunctionName = var.lambda_query_function_name }
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name          = "${var.project_name}-${var.environment}-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Lambda throttling detected"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = { FunctionName = var.lambda_query_function_name }
}

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${var.project_name}-${var.environment}-api-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "API Gateway 5xx errors elevated"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = { ApiName = var.api_gateway_id }
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          title  = "Query Lambda — Invocations & Errors"
          period = 300
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.lambda_query_function_name],
            ["AWS/Lambda", "Errors", "FunctionName", var.lambda_query_function_name],
          ]
        }
      },
      {
        type = "metric"
        properties = {
          title  = "Query Lambda — p50/p95/p99 Duration"
          period = 300
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", var.lambda_query_function_name, { stat = "p50" }],
            ["AWS/Lambda", "Duration", "FunctionName", var.lambda_query_function_name, { stat = "p95" }],
            ["AWS/Lambda", "Duration", "FunctionName", var.lambda_query_function_name, { stat = "p99" }],
          ]
        }
      },
      {
        type = "metric"
        properties = {
          title  = "API Gateway — Request Count & 4xx/5xx"
          period = 300
          metrics = [
            ["AWS/ApiGateway", "Count",    "ApiName", var.api_gateway_id],
            ["AWS/ApiGateway", "4XXError", "ApiName", var.api_gateway_id],
            ["AWS/ApiGateway", "5XXError", "ApiName", var.api_gateway_id],
          ]
        }
      }
    ]
  })
}

resource "aws_s3_bucket" "cloudtrail" {
  bucket = "${var.project_name}-${var.environment}-cloudtrail-${data.aws_caller_identity.current.account_id}"
  tags   = { Name = "${var.project_name}-${var.environment}-cloudtrail" }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      }
    ]
  })
}

resource "aws_cloudtrail" "main" {
  name                          = "${var.project_name}-${var.environment}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::${var.project_name}-${var.environment}-documents-${data.aws_caller_identity.current.account_id}/"]
    }
  }

  tags = { Name = "${var.project_name}-${var.environment}-trail" }

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    s3_logs { enable = true }
  }

  tags = { Name = "${var.project_name}-${var.environment}-guardduty" }
}

resource "aws_config_configuration_recorder" "main" {
  name     = "${var.project_name}-${var.environment}-config"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_iam_role" "config" {
  name = "${var.project_name}-${var.environment}-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_config_conformance_pack" "hipaa" {
  name = "${var.project_name}-${var.environment}-hipaa-pack"

  template_body = <<-EOT
    Parameters: {}
    Resources:
      S3BucketEncryptionEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: s3-bucket-server-side-encryption-enabled
          Source:
            Owner: AWS
            SourceIdentifier: S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED
      CloudTrailEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: cloudtrail-enabled
          Source:
            Owner: AWS
            SourceIdentifier: CLOUD_TRAIL_ENABLED
      GuardDutyEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: guardduty-enabled-centralized
          Source:
            Owner: AWS
            SourceIdentifier: GUARDDUTY_ENABLED_CENTRALIZED
      MFAEnabledForIAMConsoleAccess:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: mfa-enabled-for-iam-console-access
          Source:
            Owner: AWS
            SourceIdentifier: MFA_ENABLED_FOR_IAM_CONSOLE_ACCESS
  EOT

  depends_on = [aws_config_configuration_recorder.main]
}

output "sns_topic_arn"    { value = aws_sns_topic.alerts.arn }
output "cloudtrail_arn"   { value = aws_cloudtrail.main.arn }
output "guardduty_id"     { value = aws_guardduty_detector.main.id }
