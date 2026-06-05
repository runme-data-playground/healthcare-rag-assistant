variable "project_name" {}
variable "environment" {}
variable "kms_key_arn" {}
variable "vpc_id" {}
variable "private_subnet_ids" {}
variable "opensearch_vector_dimension" {}

data "aws_caller_identity" "current" {}

locals {
  collection_name = "${var.project_name}-${var.environment}-vectors"
}

resource "aws_opensearchserverless_security_policy" "encryption" {
  name = "${var.project_name}-${var.environment}-enc"
  type = "encryption"
  policy = jsonencode({
    Rules = [{
      ResourceType = "collection"
      Resource     = ["collection/${local.collection_name}"]
    }]
    AWSOwnedKey = false
    KmsARN      = var.kms_key_arn
  })
}

resource "aws_opensearchserverless_security_policy" "network" {
  name = "${var.project_name}-${var.environment}-net"
  type = "network"
  policy = jsonencode([{
    Rules = [
      { ResourceType = "collection"; Resource = ["collection/${local.collection_name}"] },
      { ResourceType = "dashboard";  Resource = ["collection/${local.collection_name}"] }
    ]
    AllowFromPublic = false
    SourceVPCEs     = [aws_opensearchserverless_vpc_endpoint.main.id]
  }])

  depends_on = [aws_opensearchserverless_vpc_endpoint.main]
}

resource "aws_opensearchserverless_vpc_endpoint" "main" {
  name               = "${var.project_name}-${var.environment}-vpce"
  vpc_id             = var.vpc_id
  subnet_ids         = var.private_subnet_ids
}

resource "aws_opensearchserverless_access_policy" "main" {
  name = "${var.project_name}-${var.environment}-access"
  type = "data"
  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "index"
        Resource     = ["index/${local.collection_name}/*"]
        Permission   = ["aoss:ReadDocument", "aoss:WriteDocument", "aoss:CreateIndex", "aoss:DescribeIndex"]
      },
      {
        ResourceType = "collection"
        Resource     = ["collection/${local.collection_name}"]
        Permission   = ["aoss:CreateCollectionItems", "aoss:DescribeCollectionItems"]
      }
    ]
    Principal = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-${var.environment}-lambda-role",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-${var.environment}-bedrock-role"
    ]
  }])
}

resource "aws_opensearchserverless_collection" "main" {
  name = local.collection_name
  type = "VECTORSEARCH"

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
  ]

  tags = { Name = local.collection_name }
}

output "collection_arn"      { value = aws_opensearchserverless_collection.main.arn }
output "collection_endpoint" { value = aws_opensearchserverless_collection.main.collection_endpoint }
output "collection_name"     { value = local.collection_name }
