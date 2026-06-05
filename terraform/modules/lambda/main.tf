variable "project_name" {}
variable "environment" {}
variable "memory_mb" {}
variable "timeout_seconds" {}
variable "vpc_id" {}
variable "private_subnet_ids" {}
variable "kms_key_arn" {}
variable "knowledge_base_id" {}
variable "bedrock_model_id" {}
variable "opensearch_endpoint" {}
variable "documents_bucket_name" {}
variable "bedrock_guardrail_id" {}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-${var.environment}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_bedrock" {
  name = "lambda-bedrock-access"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock-agent-runtime:Retrieve",
          "bedrock-agent-runtime:RetrieveAndGenerate",
          "bedrock-agent-runtime:StartIngestionJob",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${var.documents_bucket_name}",
          "arn:aws:s3:::${var.documents_bucket_name}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["aoss:APIAccessAll"]
        Resource = "arn:aws:aoss:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:collection/*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = var.kms_key_arn
      },
      {
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-${var.environment}-*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })
}

data "aws_security_group" "lambda" {
  tags = {
    Name = "${var.project_name}-${var.environment}-lambda-sg"
  }
}

data "archive_file" "query_handler" {
  type        = "zip"
  source_dir  = "${path.root}/../lambda/query_handler"
  output_path = "/tmp/query_handler.zip"
}

data "archive_file" "ingestion_handler" {
  type        = "zip"
  source_dir  = "${path.root}/../lambda/ingestion_handler"
  output_path = "/tmp/ingestion_handler.zip"
}

resource "aws_lambda_function" "query_handler" {
  function_name    = "${var.project_name}-${var.environment}-query-handler"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.query_handler.output_path
  source_code_hash = data.archive_file.query_handler.output_base64sha256
  memory_size      = var.memory_mb
  timeout          = var.timeout_seconds

  environment {
    variables = {
      KNOWLEDGE_BASE_ID    = var.knowledge_base_id
      BEDROCK_MODEL_ID     = var.bedrock_model_id
      OPENSEARCH_ENDPOINT  = var.opensearch_endpoint
      GUARDRAIL_ID         = var.bedrock_guardrail_id
      ENVIRONMENT          = var.environment
      LOG_LEVEL            = var.environment == "prod" ? "WARNING" : "INFO"
    }
  }

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [data.aws_security_group.lambda.id]
  }

  kms_key_arn = var.kms_key_arn

  tracing_config { mode = "Active" }

  tags = { Name = "${var.project_name}-${var.environment}-query-handler" }
}

resource "aws_lambda_provisioned_concurrency_config" "query_handler" {
  function_name                  = aws_lambda_function.query_handler.function_name
  qualifier                      = aws_lambda_alias.query_handler_live.name
  provisioned_concurrent_executions = 2
}

resource "aws_lambda_alias" "query_handler_live" {
  name             = "live"
  function_name    = aws_lambda_function.query_handler.function_name
  function_version = aws_lambda_function.query_handler.version
}

resource "aws_lambda_function" "ingestion_handler" {
  function_name    = "${var.project_name}-${var.environment}-ingestion-handler"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.ingestion_handler.output_path
  source_code_hash = data.archive_file.ingestion_handler.output_base64sha256
  memory_size      = 512
  timeout          = 300

  environment {
    variables = {
      KNOWLEDGE_BASE_ID = var.knowledge_base_id
      ENVIRONMENT       = var.environment
    }
  }

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [data.aws_security_group.lambda.id]
  }

  tracing_config { mode = "Active" }

  tags = { Name = "${var.project_name}-${var.environment}-ingestion-handler" }
}

output "query_handler_arn"        { value = aws_lambda_function.query_handler.arn }
output "query_handler_invoke_arn" { value = aws_lambda_function.query_handler.invoke_arn }
output "query_handler_name"       { value = aws_lambda_function.query_handler.function_name }
output "ingestion_handler_arn"    { value = aws_lambda_function.ingestion_handler.arn }
output "ingestion_handler_name"   { value = aws_lambda_function.ingestion_handler.function_name }
