module "kms" {
  source       = "./modules/kms"
  project_name = var.project_name
  environment  = var.environment
}

module "vpc" {
  source               = "./modules/vpc"
  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  private_subnet_cidrs = var.private_subnet_cidrs
  aws_region           = var.aws_region
}

module "s3" {
  source       = "./modules/s3"
  project_name = var.project_name
  environment  = var.environment
  kms_key_arn  = module.kms.s3_key_arn
}

module "opensearch" {
  source                      = "./modules/opensearch"
  project_name                = var.project_name
  environment                 = var.environment
  kms_key_arn                 = module.kms.opensearch_key_arn
  vpc_id                      = module.vpc.vpc_id
  private_subnet_ids          = module.vpc.private_subnet_ids
  opensearch_vector_dimension = var.opensearch_vector_dimension
}

module "cognito" {
  source                    = "./modules/cognito"
  project_name              = var.project_name
  environment               = var.environment
  mfa_configuration         = var.cognito_mfa_configuration
}

module "waf" {
  source       = "./modules/waf"
  project_name = var.project_name
  environment  = var.environment
}

module "bedrock" {
  source                     = "./modules/bedrock"
  project_name               = var.project_name
  environment                = var.environment
  s3_bucket_arn              = module.s3.documents_bucket_arn
  s3_bucket_name             = module.s3.documents_bucket_name
  opensearch_collection_arn  = module.opensearch.collection_arn
  bedrock_embedding_model_id = var.bedrock_embedding_model_id
  bedrock_model_id           = var.bedrock_model_id
  kms_key_arn                = module.kms.bedrock_key_arn
}

module "lambda" {
  source                    = "./modules/lambda"
  project_name              = var.project_name
  environment               = var.environment
  memory_mb                 = var.lambda_memory_mb
  timeout_seconds           = var.lambda_timeout_seconds
  vpc_id                    = module.vpc.vpc_id
  private_subnet_ids        = module.vpc.private_subnet_ids
  kms_key_arn               = module.kms.lambda_key_arn
  knowledge_base_id         = module.bedrock.knowledge_base_id
  bedrock_model_id          = var.bedrock_model_id
  opensearch_endpoint       = module.opensearch.collection_endpoint
  documents_bucket_name     = module.s3.documents_bucket_name
  bedrock_guardrail_id      = module.bedrock.guardrail_id
}

module "api_gateway" {
  source              = "./modules/api_gateway"
  project_name        = var.project_name
  environment         = var.environment
  lambda_invoke_arn   = module.lambda.query_handler_invoke_arn
  lambda_function_arn = module.lambda.query_handler_arn
  cognito_user_pool_arn = module.cognito.user_pool_arn
  waf_acl_arn         = module.waf.acl_arn
  throttle_rate       = var.api_throttle_rate
  throttle_burst      = var.api_throttle_burst
}

module "eventbridge" {
  source              = "./modules/eventbridge"
  project_name        = var.project_name
  environment         = var.environment
  ingestion_schedule  = var.ingestion_schedule
  lambda_function_arn = module.lambda.ingestion_handler_arn
  knowledge_base_id   = module.bedrock.knowledge_base_id
  data_source_id      = module.bedrock.data_source_id
}

module "monitoring" {
  source                    = "./modules/monitoring"
  project_name              = var.project_name
  environment               = var.environment
  alert_email               = var.alert_email
  lambda_query_function_name     = module.lambda.query_handler_name
  lambda_ingestion_function_name = module.lambda.ingestion_handler_name
  api_gateway_id            = module.api_gateway.api_id
  aws_region                = var.aws_region
}
