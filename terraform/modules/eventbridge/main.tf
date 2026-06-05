variable "project_name" {}
variable "environment" {}
variable "ingestion_schedule" {}
variable "lambda_function_arn" {}
variable "knowledge_base_id" {}
variable "data_source_id" {}

resource "aws_iam_role" "eventbridge" {
  name = "${var.project_name}-${var.environment}-eventbridge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge_lambda" {
  name = "invoke-ingestion-lambda"
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = var.lambda_function_arn
    }]
  })
}

resource "aws_scheduler_schedule" "ingestion" {
  name       = "${var.project_name}-${var.environment}-ingestion"
  group_name = "default"

  flexible_time_window { mode = "OFF" }
  schedule_expression = var.ingestion_schedule

  target {
    arn      = var.lambda_function_arn
    role_arn = aws_iam_role.eventbridge.arn

    input = jsonencode({
      knowledge_base_id = var.knowledge_base_id
      data_source_id    = var.data_source_id
      trigger           = "scheduled"
    })

    retry_policy {
      maximum_retry_attempts       = 3
      maximum_event_age_in_seconds = 3600
    }
  }
}

resource "aws_cloudwatch_event_rule" "s3_new_document" {
  name        = "${var.project_name}-${var.environment}-s3-new-doc"
  description = "Trigger ingestion when new document uploaded to S3"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = { name = [{ prefix = "${var.project_name}-${var.environment}-documents" }] }
    }
  })
}

resource "aws_cloudwatch_event_target" "s3_new_document" {
  rule = aws_cloudwatch_event_rule.s3_new_document.name
  arn  = var.lambda_function_arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_arn
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.s3_new_document.arn
}
