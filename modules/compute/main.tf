# ═══════════════════════════════════════════════════════════
# COMPUTE MODULE — Configuration & Locals
# ═══════════════════════════════════════════════════════════
# Questo modulo gestisce:
#   - ECS Cluster con Fargate + Fargate Spot
#   - ECR Repositories per le 3 immagini container
#   - Application Load Balancer (ALB) con HTTPS
#   - 3 Servizi ECS:
#       1. Web/API     — dietro ALB, user-facing
#       2. ETL Worker  — poll SQS, Fargate Spot
#       3. Report Worker — poll SQS, genera PDF
#   - Auto Scaling policies per ciascun servizio
#
# Le risorse sono definite in:
#   - ecs_cluster.tf    → cluster, ECR, ALB
#   - service_web.tf    → task definition + service Web/API
#   - service_etl.tf    → task definition + service ETL
#   - service_reports.tf → task definition + service Report
#   - autoscaling.tf    → scaling policies e alarms
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
  compute_tags = {
    Layer = "compute"
  }

  # Configurazione risorse per ogni servizio
  service_config = {
    web_api = {
      cpu    = 1024 # 1 vCPU
      memory = 2048 # 2 GB
      port   = 8080
    }
    etl_worker = {
      cpu    = 4096 # 4 vCPU — processing pesante
      memory = 8192 # 8 GB — streaming file grandi
    }
    report_worker = {
      cpu    = 2048 # 2 vCPU
      memory = 4096 # 4 GB — PDF generation
    }
  }

  # CPU architecture — ARM64 (Graviton) per miglior rapporto prezzo/perf
  cpu_architecture        = "ARM64"
  operating_system_family = "LINUX"
}