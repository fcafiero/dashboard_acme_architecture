# ═══════════════════════════════════════════════════════════
# DATABASE MODULE — Configuration & Locals
# ═══════════════════════════════════════════════════════════
# Questo modulo gestisce:
#   - Aurora PostgreSQL (Writer + auto-scaling Readers)
#   - ElastiCache Redis (Multi-AZ con failover)
#   - Secrets Manager per le credenziali
#
# Le risorse sono definite in:
#   - aurora.tf → cluster Aurora, istanze, auto-scaling
#   - redis.tf  → replication group Redis
#
# Tutte le risorse risiedono nelle subnet private del
# data layer e sono accessibili solo dai security group
# dei servizi ECS autorizzati.
# ═══════════════════════════════════════════════════════════

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

locals {
  db_tags = {
    Layer = "data"
  }

  # Parametri Aurora derivati
  aurora_engine         = "aurora-postgresql"
  aurora_engine_version = "16.4"
  aurora_family         = "aurora-postgresql16"
  aurora_database_name  = "acme_dashboard"
  aurora_master_user    = "acme_admin"
  aurora_port           = 5432

  # Parametri Redis derivati
  redis_engine         = "redis"
  redis_engine_version = "7.1"
  redis_port           = 6379
  redis_family         = "redis7"
}