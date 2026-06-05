variable "project_name" {}
variable "environment" {}
variable "kms_key_arn" {}

resource "aws_s3_bucket" "documents" {
  bucket = "${var.project_name}-${var.environment}-documents-${data.aws_caller_identity.current.account_id}"

  tags = { Name = "${var.project_name}-${var.environment}-documents" }
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket                  = aws_s3_bucket.documents.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"
    filter { prefix = "" }
    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }
    noncurrent_version_expiration { noncurrent_days = 365 }
  }
}

resource "aws_s3_bucket_notification" "documents" {
  bucket      = aws_s3_bucket.documents.id
  eventbridge = true
}

resource "aws_s3_object" "prefixes" {
  for_each = toset([
    "clinical-guidelines/",
    "drug-formulary/",
    "protocols/",
    "discharge-summaries/",
    "lab-references/",
    "compliance/",
  ])
  bucket  = aws_s3_bucket.documents.id
  key     = each.value
  content = ""
}

output "documents_bucket_name" { value = aws_s3_bucket.documents.id }
output "documents_bucket_arn"  { value = aws_s3_bucket.documents.arn }
