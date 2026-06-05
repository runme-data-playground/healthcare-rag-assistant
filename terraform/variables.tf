variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name used as prefix for all resources"
  type        = string
  default     = "healthcare-rag"
}

variable "bedrock_model_id" {
  description = "Bedrock generation model ARN"
  type        = string
  default     = "anthropic.claude-3-5-sonnet-20241022-v2:0"
}

variable "bedrock_embedding_model_id" {
  description = "Bedrock embedding model ARN"
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}

variable "opensearch_vector_dimension" {
  description = "Embedding vector dimension (must match embedding model)"
  type        = number
  default     = 1024
}

variable "lambda_memory_mb" {
  description = "Lambda function memory in MB"
  type        = number
  default     = 1024
}

variable "lambda_timeout_seconds" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
}

variable "api_throttle_rate" {
  description = "API Gateway steady-state request rate (requests/sec)"
  type        = number
  default     = 100
}

variable "api_throttle_burst" {
  description = "API Gateway burst request limit"
  type        = number
  default     = 200
}

variable "cognito_mfa_configuration" {
  description = "Cognito MFA setting: OFF, ON, or OPTIONAL"
  type        = string
  default     = "ON"
}

variable "alert_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
}

variable "ingestion_schedule" {
  description = "EventBridge schedule for document ingestion (cron expression)"
  type        = string
  default     = "cron(0 2 * * ? *)"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}
