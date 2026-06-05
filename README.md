# Healthcare AWS RAG Assistant

A production-ready, HIPAA-aligned Retrieval-Augmented Generation (RAG) assistant built on AWS, designed for healthcare professionals to query clinical guidelines, drug formularies, and institutional protocols using natural language.

## Architecture Overview

```
User → WAF → Cognito → API Gateway → Lambda → Bedrock → S3 + OpenSearch
```

### Full service inventory

| Layer | Service | Purpose |
|---|---|---|
| Security | Amazon Cognito | User pools, JWT auth, MFA |
| Security | AWS WAF | Threat filtering, rate limits, prompt injection protection |
| Security | AWS KMS | Encryption key management |
| Security | AWS Secrets Manager | API keys, credentials |
| Security | IAM | Least-privilege roles |
| Security | Amazon GuardDuty | Threat detection |
| Networking | Amazon VPC | Private network boundary |
| Networking | VPC Endpoints | Private access to Bedrock, S3, OpenSearch |
| API | Amazon API Gateway | REST endpoint, throttling, Cognito authorizer |
| Compute | AWS Lambda | RAG orchestration, ingestion pipeline |
| AI | Amazon Bedrock | LLM generation (Claude 3.5 Sonnet), embeddings (Titan V2) |
| AI | Bedrock Knowledge Base | Managed chunking, embedding, sync |
| AI | Bedrock Guardrails | Content filtering, PII redaction |
| Storage | Amazon S3 | Medical documents, PDFs, clinical guidelines |
| Search | Amazon OpenSearch Serverless | Vector index, semantic retrieval |
| Eventing | Amazon EventBridge | Scheduled ingestion triggers |
| Observability | Amazon CloudWatch | Metrics, logs, alarms |
| Observability | AWS X-Ray | Distributed tracing |
| Observability | AWS CloudTrail | API audit log (HIPAA) |
| Observability | AWS Config | Compliance posture |
| Notifications | Amazon SNS | Alarm notifications |

## Repository Structure

```
healthcare-rag-assistant/
├── terraform/
│   ├── main.tf                    # Root module
│   ├── variables.tf               # Input variables
│   ├── outputs.tf                 # Stack outputs
│   ├── providers.tf               # AWS provider config
│   └── modules/
│       ├── vpc/                   # VPC, subnets, VPC endpoints
│       ├── cognito/               # User pool, groups, MFA
│       ├── waf/                   # WAF ACL, managed rules
│       ├── api_gateway/           # REST API, Cognito authorizer
│       ├── lambda/                # Query + ingestion functions
│       ├── bedrock/               # Knowledge base, guardrails
│       ├── opensearch/            # Serverless collection, index
│       ├── s3/                    # Document buckets, lifecycle
│       ├── kms/                   # Encryption keys
│       ├── eventbridge/           # Ingestion schedule
│       └── monitoring/            # CloudWatch, X-Ray, CloudTrail, SNS
├── lambda/
│   ├── query_handler/             # RAG query orchestration
│   │   ├── handler.py
│   │   ├── retrieval.py
│   │   ├── prompt_builder.py
│   │   ├── response_parser.py
│   │   └── requirements.txt
│   └── ingestion_handler/         # Document ingestion trigger
│       ├── handler.py
│       └── requirements.txt
├── docs/
│   └── architecture.md            # Detailed architecture notes
└── scripts/
    ├── deploy.sh                  # Deploy stack
    └── upload_docs.sh             # Upload sample documents to S3
```

## Prerequisites

- AWS CLI v2 configured with appropriate permissions
- Terraform >= 1.5
- Python 3.12
- An AWS account with Bedrock model access enabled for:
  - `anthropic.claude-3-5-sonnet-20241022-v2:0`
  - `amazon.titan-embed-text-v2:0`

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/runme-data-playground/healthcare-rag-assistant.git
cd healthcare-rag-assistant

# 2. Deploy infrastructure
cd terraform
terraform init
terraform plan -var-file="terraform.tfvars.example"
terraform apply

# 3. Upload sample documents
cd ..
./scripts/upload_docs.sh

# 4. Trigger initial Knowledge Base sync
aws bedrock-agent start-ingestion-job \
  --knowledge-base-id $(terraform -chdir=terraform output -raw knowledge_base_id) \
  --data-source-id $(terraform -chdir=terraform output -raw data_source_id)

# 5. Test the endpoint
curl -X POST $(terraform -chdir=terraform output -raw api_endpoint)/query \
  -H "Authorization: Bearer <cognito_jwt_token>" \
  -H "Content-Type: application/json" \
  -d '{"query": "What is the recommended first-line treatment for Type 2 diabetes with CKD stage 3?"}'
```

## HIPAA Alignment

This architecture addresses the following HIPAA Technical Safeguard requirements:

- **Access Control** — Cognito user pools with MFA, IAM least-privilege roles, VPC isolation
- **Audit Controls** — CloudTrail API logging, CloudWatch structured logs, X-Ray tracing
- **Integrity** — KMS encryption at rest, TLS in transit, S3 versioning
- **Transmission Security** — VPC endpoints eliminate public internet exposure for all internal traffic
- **Automatic Logoff** — Cognito token expiration (configurable, default 1 hour)

> ⚠️ This repository provides infrastructure code for reference. Consult your compliance officer and sign an AWS Business Associate Agreement (BAA) before processing real ePHI.

## License

MIT
