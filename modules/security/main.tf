# ═══════════════════════════════════════════════════════════
# SECURITY MODULE — Provider Configuration + CloudTrail
# ═══════════════════════════════════════════════════════════
# Questo modulo usa DUE provider AWS:
#   - aws          → region principale (KMS, IAM, CloudTrail)
#   - aws.us_east_1 → us-east-1 (WAF per CloudFront)
#
# Il WAF con scope CLOUDFRONT DEVE essere creato in us-east-1.
# ═══════════════════════════════════════════════════════════

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.60"
      configuration_aliases = [aws.us_east_1]
    }
  }
}

# ── Data Sources ────────────────────────────────────────

data "aws_caller_identity" "current" {}

# ── CloudTrail per audit completo ───────────────────────

resource "aws_s3_bucket" "cloudtrail" {
  bucket_prefix = "${var.name_prefix}-cloudtrail-"
  force_destroy = true

  tags = {
    Name  = "${var.name_prefix}-cloudtrail-logs"
    Layer = "security"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

resource "aws_cloudtrail" "main" {
  name                          = "${var.name_prefix}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.main.arn

  tags = {
    Name  = "${var.name_prefix}-cloudtrail"
    Layer = "security"
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}