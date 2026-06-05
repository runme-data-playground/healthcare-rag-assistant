variable "project_name" {}
variable "environment" {}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

resource "aws_kms_key" "s3" {
  description             = "KMS key for S3 healthcare documents encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "Enable IAM User Permissions"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid    = "Allow S3 Service"
        Effect = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = "*"
      }
    ]
  })

  tags = { Name = "${var.project_name}-${var.environment}-s3-key" }
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${var.project_name}-${var.environment}-s3"
  target_key_id = aws_kms_key.s3.key_id
}

resource "aws_kms_key" "opensearch" {
  description             = "KMS key for OpenSearch Serverless encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = { Name = "${var.project_name}-${var.environment}-opensearch-key" }
}

resource "aws_kms_alias" "opensearch" {
  name          = "alias/${var.project_name}-${var.environment}-opensearch"
  target_key_id = aws_kms_key.opensearch.key_id
}

resource "aws_kms_key" "lambda" {
  description             = "KMS key for Lambda environment variable encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = { Name = "${var.project_name}-${var.environment}-lambda-key" }
}

resource "aws_kms_alias" "lambda" {
  name          = "alias/${var.project_name}-${var.environment}-lambda"
  target_key_id = aws_kms_key.lambda.key_id
}

resource "aws_kms_key" "bedrock" {
  description             = "KMS key for Bedrock Knowledge Base encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = { Name = "${var.project_name}-${var.environment}-bedrock-key" }
}

resource "aws_kms_alias" "bedrock" {
  name          = "alias/${var.project_name}-${var.environment}-bedrock"
  target_key_id = aws_kms_key.bedrock.key_id
}

output "s3_key_arn"         { value = aws_kms_key.s3.arn }
output "opensearch_key_arn" { value = aws_kms_key.opensearch.arn }
output "lambda_key_arn"     { value = aws_kms_key.lambda.arn }
output "bedrock_key_arn"    { value = aws_kms_key.bedrock.arn }
