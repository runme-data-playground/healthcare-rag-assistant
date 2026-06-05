#!/usr/bin/env bash
set -euo pipefail

BUCKET_NAME=${1:-""}
ENVIRONMENT=${2:-dev}

if [ -z "$BUCKET_NAME" ]; then
  BUCKET_NAME=$(terraform -chdir=terraform output -raw documents_bucket_name)
fi

echo "Uploading sample documents to s3://$BUCKET_NAME"

PREFIXES=(
  "clinical-guidelines"
  "drug-formulary"
  "protocols"
  "discharge-summaries"
  "lab-references"
  "compliance"
)

for prefix in "${PREFIXES[@]}"; do
  if [ -d "docs/samples/$prefix" ]; then
    echo "Uploading $prefix/..."
    aws s3 sync "docs/samples/$prefix/" "s3://$BUCKET_NAME/$prefix/" \
      --sse aws:kms \
      --no-progress
  else
    echo "No sample docs found for $prefix — skipping."
  fi
done

echo ""
echo "Upload complete. Trigger a Knowledge Base sync to index new documents:"
echo "  aws bedrock-agent start-ingestion-job \\"
echo "    --knowledge-base-id \$(terraform -chdir=terraform output -raw knowledge_base_id) \\"
echo "    --data-source-id \$(terraform -chdir=terraform output -raw data_source_id)"
