# ═══════════════════════════════════════════════════════════
# MESSAGING MODULE — Provider Configuration
# ═══════════════════════════════════════════════════════════

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

# ═══════════════════════════════════════════════════════════
# SQS QUEUES — ETL Ingestion + Report Generation
# ═══════════════════════════════════════════════════════════
# Ogni coda ha la propria Dead Letter Queue (DLQ).
# Le DLQ sono monitorate con CloudWatch Alarms.
# ═══════════════════════════════════════════════════════════

# ── ETL INGESTION QUEUE ─────────────────────────────────

resource "aws_sqs_queue" "etl_dlq" {
  name = "${var.name_prefix}-etl-dlq"

  message_retention_seconds = 1209600 # 14 giorni — massimo, per debug

  kms_master_key_id                 = var.kms_key_arn
  kms_data_key_reuse_period_seconds = 300

  tags = {
    Name = "${var.name_prefix}-etl-dlq"
  }
}

resource "aws_sqs_queue" "etl" {
  name = "${var.name_prefix}-etl-ingestion"

  # Timeout di visibilità > tempo massimo di elaborazione di un file
  visibility_timeout_seconds = 1800 # 30 minuti per file >2GB
  message_retention_seconds  = 1209600 # 14 giorni
  receive_wait_time_seconds  = 20 # Long polling — riduce costi

  kms_master_key_id                 = var.kms_key_arn
  kms_data_key_reuse_period_seconds = 300

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.etl_dlq.arn
    maxReceiveCount     = 3 # Dopo 3 tentativi falliti → DLQ
  })

  tags = {
    Name = "${var.name_prefix}-etl-ingestion"
  }
}

# Policy per permettere a S3 di inviare notifiche alla coda
resource "aws_sqs_queue_policy" "etl_s3" {
  queue_url = aws_sqs_queue.etl.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowS3Notification"
      Effect = "Allow"
      Principal = {
        Service = "s3.amazonaws.com"
      }
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.etl.arn
    }]
  })
}

# ── REPORT GENERATION QUEUE ─────────────────────────────

resource "aws_sqs_queue" "report_dlq" {
  name = "${var.name_prefix}-report-dlq"

  message_retention_seconds = 1209600

  kms_master_key_id                 = var.kms_key_arn
  kms_data_key_reuse_period_seconds = 300

  tags = {
    Name = "${var.name_prefix}-report-dlq"
  }
}

resource "aws_sqs_queue" "report" {
  name = "${var.name_prefix}-report-generation"

  visibility_timeout_seconds = 900 # 15 minuti
  message_retention_seconds  = 1209600
  receive_wait_time_seconds  = 20

  kms_master_key_id                 = var.kms_key_arn
  kms_data_key_reuse_period_seconds = 300

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.report_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name = "${var.name_prefix}-report-generation"
  }
}