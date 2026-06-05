#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT=${1:-dev}
AWS_REGION=${2:-us-east-1}

echo "Deploying Healthcare RAG Assistant — environment: $ENVIRONMENT, region: $AWS_REGION"

echo "Installing Lambda dependencies..."
pip install -r lambda/query_handler/requirements.txt \
  -t lambda/query_handler/package --upgrade --quiet
pip install -r lambda/ingestion_handler/requirements.txt \
  -t lambda/ingestion_handler/package --upgrade --quiet

echo "Initialising Terraform..."
cd terraform
terraform init -upgrade

echo "Planning..."
terraform plan \
  -var="environment=$ENVIRONMENT" \
  -var="aws_region=$AWS_REGION" \
  -out=tfplan

echo "Applying..."
terraform apply tfplan

echo ""
echo "Deployment complete."
echo "API endpoint: $(terraform output -raw api_endpoint)"
echo "Knowledge Base ID: $(terraform output -raw knowledge_base_id)"
echo "Documents bucket: $(terraform output -raw documents_bucket_name)"
