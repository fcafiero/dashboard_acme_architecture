# ═══════════════════════════════════════════════════════════
# VARIABILI GLOBALI DEL PROGETTO
# ═══════════════════════════════════════════════════════════

variable "project_name" {
  description = "Nome del progetto, usato come prefisso per tutte le risorse"
  type        = string
  default     = "acme-dashboard"
}

variable "environment" {
  description = "Ambiente di deployment"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# ══════════════════════════════════════════════════════════
# REGION — Configurabile, default Milano
# ══════════════════════════════════════════════════════════
variable "aws_region" {
  description = "AWS Region principale per il deployment dell'infrastruttura"
  type        = string
  default     = "eu-south-1" # Milano

  validation {
    condition = contains([
      "eu-south-1",  # Milano
      "eu-west-1",   # Irlanda
      "eu-west-2",   # Londra
      "eu-west-3",   # Parigi
      "eu-central-1", # Francoforte
      "eu-central-2", # Zurigo
      "eu-north-1",  # Stoccolma
      "us-east-1",   # N. Virginia
      "us-west-2",   # Oregon
    ], var.aws_region)
    error_message = "Region must be a supported AWS region."
  }
}

variable "domain_name" {
  description = "Dominio principale dell'applicazione"
  type        = string
  default     = "dashboard.acme.com"
}

variable "hosted_zone_name" {
  description = "Nome della hosted zone Route 53"
  type        = string
  default     = "acme.com"
}

# ── VPC ──────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block per la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# ══════════════════════════════════════════════════════════
# AZ — Derivate automaticamente dalla region, sovrascrivibili
# ══════════════════════════════════════════════════════════
variable "availability_zones" {
  description = "Lista delle AZ da utilizzare. Se vuota, vengono derivate automaticamente dalla region."
  type        = list(string)
  default     = [] # Vuoto → risolte dinamicamente
}

# ── Database ─────────────────────────────────────────────
variable "aurora_instance_class" {
  description = "Instance class per Aurora"
  type        = string
  default     = "db.r6g.large"
}

variable "aurora_min_reader_count" {
  description = "Numero minimo di reader replicas"
  type        = number
  default     = 1
}

variable "aurora_max_reader_count" {
  description = "Numero massimo di reader replicas"
  type        = number
  default     = 5
}

variable "redis_node_type" {
  description = "Tipo di nodo ElastiCache Redis"
  type        = string
  default     = "cache.r6g.large"
}

# ── ECS ──────────────────────────────────────────────────
variable "web_api_image" {
  description = "URI dell'immagine Docker per Web/API"
  type        = string
  default     = ""
}

variable "etl_worker_image" {
  description = "URI dell'immagine Docker per ETL Worker"
  type        = string
  default     = ""
}

variable "report_worker_image" {
  description = "URI dell'immagine Docker per Report Worker"
  type        = string
  default     = ""
}

# ── Scaling ──────────────────────────────────────────────
variable "web_min_capacity" {
  description = "Numero minimo di task Web/API"
  type        = number
  default     = 2
}

variable "web_max_capacity" {
  description = "Numero massimo di task Web/API"
  type        = number
  default     = 10
}

variable "etl_min_capacity" {
  description = "Numero minimo di task ETL (0 = scale to zero)"
  type        = number
  default     = 0
}

variable "etl_max_capacity" {
  description = "Numero massimo di task ETL"
  type        = number
  default     = 20
}

variable "report_min_capacity" {
  description = "Numero minimo di task Report"
  type        = number
  default     = 0
}

variable "report_max_capacity" {
  description = "Numero massimo di task Report"
  type        = number
  default     = 10
}

# ── Alerting ─────────────────────────────────────────────
variable "alert_email" {
  description = "Email per le notifiche di allarme"
  type        = string
}

variable "ses_verified_domain" {
  description = "Dominio verificato in SES per invio email"
  type        = string
  default     = "acme.com"
}