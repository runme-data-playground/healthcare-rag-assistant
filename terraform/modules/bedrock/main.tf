variable "project_name" {}
variable "environment" {}
variable "s3_bucket_arn" {}
variable "s3_bucket_name" {}
variable "opensearch_collection_arn" {}
variable "bedrock_embedding_model_id" {}
variable "bedrock_model_id" {}
variable "kms_key_arn" {}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_role" "bedrock" {
  name = "${var.project_name}-${var.environment}-bedrock-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "bedrock_s3" {
  name = "bedrock-s3-access"
  role = aws_iam_role.bedrock.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [var.s3_bucket_arn, "${var.s3_bucket_arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = var.kms_key_arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "bedrock_opensearch" {
  name = "bedrock-opensearch-access"
  role = aws_iam_role.bedrock.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["aoss:APIAccessAll"]
      Resource = var.opensearch_collection_arn
    }]
  })
}

resource "aws_bedrockagent_knowledge_base" "main" {
  name     = "${var.project_name}-${var.environment}-kb"
  role_arn = aws_iam_role.bedrock.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/${var.bedrock_embedding_model_id}"
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = var.opensearch_collection_arn
      vector_index_name = "healthcare-docs-index"
      field_mapping {
        vector_field   = "vector_field"
        text_field     = "text"
        metadata_field = "metadata"
      }
    }
  }

  tags = { Name = "${var.project_name}-${var.environment}-kb" }
}

resource "aws_bedrockagent_data_source" "s3" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.main.id
  name              = "${var.project_name}-${var.environment}-s3-source"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = var.s3_bucket_arn
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "SEMANTIC"
      semantic_chunking_configuration {
        max_token       = 512
        buffer_size     = 1
        breakpoint_percentile_threshold = 95
      }
    }
  }
}

resource "aws_bedrock_guardrail" "main" {
  name                      = "${var.project_name}-${var.environment}-guardrail"
  blocked_input_messaging   = "I cannot process this request. Please rephrase your clinical query."
  blocked_outputs_messaging = "The response was blocked by content safety filters."

  content_policy_config {
    filters_config {
      type            = "HATE"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "VIOLENCE"
      input_strength  = "MEDIUM"
      output_strength = "MEDIUM"
    }
  }

  sensitive_information_policy_config {
    pii_entities_config {
      type   = "EMAIL"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "PHONE"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "US_SOCIAL_SECURITY_NUMBER"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "NAME"
      action = "ANONYMIZE"
    }
  }

  topic_policy_config {
    topics_config {
      name       = "SpecificTreatmentRecommendation"
      definition = "Requests for specific treatment recommendations for individual patients"
      examples   = ["What should I prescribe for my patient?", "Should I operate on this patient?"]
      type       = "DENY"
    }
  }

  tags = { Name = "${var.project_name}-${var.environment}-guardrail" }
}

output "knowledge_base_id" { value = aws_bedrockagent_knowledge_base.main.id }
output "data_source_id"    { value = aws_bedrockagent_data_source.s3.data_source_id }
output "guardrail_id"      { value = aws_bedrock_guardrail.main.guardrail_id }
output "guardrail_arn"     { value = aws_bedrock_guardrail.main.guardrail_arn }
