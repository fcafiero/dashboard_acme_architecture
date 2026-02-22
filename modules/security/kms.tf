# ═══════════════════════════════════════════════════════════
# KMS — Customer Managed Key per la crittografia
# ═══════════════════════════════════════════════════════════
# Una singola CMK usata per: S3, Aurora, SQS, Secrets Manager
# In produzione, si potrebbe separare per dominio di dati
# ═══════════════════════════════════════════════════════════

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "main" {
  description             = "CMK for ${var.name_prefix} - encrypts S3, Aurora, SQS, Secrets"
  deletion_window_in_days = 30
  enable_key_rotation     = true # Rotazione automatica ogni anno

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "key-policy-1"
    Statement = [
      {
        Sid    = "EnableRootAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowServiceAccess"
        Effect = "Allow"
        Principal = {
          Service = [
            "s3.amazonaws.com",
            "sqs.amazonaws.com",
            "rds.amazonaws.com",
            "secretsmanager.amazonaws.com",
            "logs.amazonaws.com"
          ]
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.name_prefix}-cmk"
  }
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.name_prefix}"
  target_key_id = aws_kms_key.main.key_id
}