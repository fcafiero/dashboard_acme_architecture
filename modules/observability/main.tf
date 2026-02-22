# ═══════════════════════════════════════════════════════════
# OBSERVABILITY MODULE — Configuration
# ═══════════════════════════════════════════════════════════
# Questo modulo gestisce:
#   - SNS Topic per le notifiche di allarme
#   - CloudWatch Alarms per tutti i componenti critici:
#       - DLQ (messaggi falliti)
#       - SQS Queue Age (ritardi nell'elaborazione)
#       - ALB (errori 5xx, latenza p95)
#       - ECS (CPU critico)
#       - Aurora (CPU, storage)
#       - Redis (memoria)
#   - CloudWatch Dashboard operativa
#
# Le risorse sono definite in:
#   - sns.tf        → topic e subscription
#   - cloudwatch.tf → alarms e dashboard
# ═══════════════════════════════════════════════════════════

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

locals {
  observability_tags = {
    Layer = "observability"
  }
}