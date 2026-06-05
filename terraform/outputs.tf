output "api_endpoint" {
  description = "API Gateway endpoint URL"
  value       = module.api_gateway.endpoint_url
}

output "knowledge_base_id" {
  description = "Bedrock Knowledge Base ID"
  value       = module.bedrock.knowledge_base_id
}

output "data_source_id" {
  description = "Bedrock Knowledge Base data source ID"
  value       = module.bedrock.data_source_id
}

output "documents_bucket_name" {
  description = "S3 bucket name for healthcare documents"
  value       = module.s3.documents_bucket_name
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = module.cognito.user_pool_id
}

output "cognito_client_id" {
  description = "Cognito App Client ID"
  value       = module.cognito.client_id
  sensitive   = true
}

output "opensearch_endpoint" {
  description = "OpenSearch Serverless collection endpoint"
  value       = module.opensearch.collection_endpoint
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}
