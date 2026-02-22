# ═══════════════════════════════════════════════════════════
# MAIN — ORCHESTRAZIONE DI TUTTI I MODULI
# ═══════════════════════════════════════════════════════════
# Region: configurabile via var.aws_region (default: eu-south-1 Milano)
# Le AZ vengono risolte dinamicamente dalla region se non specificate.
# ═══════════════════════════════════════════════════════════

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ── Risoluzione dinamica delle Availability Zones ───────
# Se l'utente non specifica le AZ, vengono prese le prime 2
# disponibili nella region selezionata.
# ═══════════════════════════════════════════════════════════
data "aws_availability_zones" "available" {
  state = "available"

  # Escludere le Local Zones e Wavelength Zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  # Se availability_zones è vuoto, usa le prime 2 AZ della region
  resolved_azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 2)
}

# ─────────────────────────────────────────────────────────
# 1. NETWORKING
# ─────────────────────────────────────────────────────────
module "networking" {
  source = "./modules/networking"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  availability_zones = local.resolved_azs
  aws_region         = var.aws_region
}

# ─────────────────────────────────────────────────────────
# 2. SECURITY
# ─────────────────────────────────────────────────────────
module "security" {
  source = "./modules/security"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name_prefix = local.name_prefix
  vpc_id      = module.networking.vpc_id
  aws_region  = var.aws_region

  s3_raw_bucket_arn     = module.storage.s3_raw_bucket_arn
  s3_reports_bucket_arn = module.storage.s3_reports_bucket_arn
  sqs_etl_queue_arn     = module.messaging.sqs_etl_queue_arn
  sqs_report_queue_arn  = module.messaging.sqs_report_queue_arn
  aurora_cluster_arn    = module.database.aurora_cluster_arn
  kms_key_arn           = module.security.kms_key_arn

  alb_security_group_id        = module.networking.alb_security_group_id
  ecs_web_security_group_id    = module.networking.ecs_web_security_group_id
  ecs_etl_security_group_id    = module.networking.ecs_etl_security_group_id
  ecs_report_security_group_id = module.networking.ecs_report_security_group_id
}

# ─────────────────────────────────────────────────────────
# 3. STORAGE
# ─────────────────────────────────────────────────────────
module "storage" {
  source = "./modules/storage"

  name_prefix       = local.name_prefix
  kms_key_arn       = module.security.kms_key_arn
  sqs_etl_queue_arn = module.messaging.sqs_etl_queue_arn
  domain_name       = var.domain_name
}

# ─────────────────────────────────────────────────────────
# 4. MESSAGING
# ─────────────────────────────────────────────────────────
module "messaging" {
  source = "./modules/messaging"

  name_prefix = local.name_prefix
  kms_key_arn = module.security.kms_key_arn
}

# ─────────────────────────────────────────────────────────
# 5. DATABASE
# ─────────────────────────────────────────────────────────
module "database" {
  source = "./modules/database"

  name_prefix         = local.name_prefix
  vpc_id              = module.networking.vpc_id
  database_subnet_ids = module.networking.database_subnet_ids

  aurora_instance_class    = var.aurora_instance_class
  aurora_security_group_id = module.networking.aurora_security_group_id
  aurora_min_reader_count  = var.aurora_min_reader_count
  aurora_max_reader_count  = var.aurora_max_reader_count
  kms_key_arn              = module.security.kms_key_arn

  redis_node_type         = var.redis_node_type
  redis_security_group_id = module.networking.redis_security_group_id
  redis_subnet_ids        = module.networking.database_subnet_ids
}

# ─────────────────────────────────────────────────────────
# 6. COMPUTE
# ─────────────────────────────────────────────────────────
module "compute" {
  source = "./modules/compute"

  name_prefix        = local.name_prefix
  aws_region         = var.aws_region
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_app_subnet_ids
  public_subnet_ids  = module.networking.public_subnet_ids

  alb_security_group_id = module.networking.alb_security_group_id
  acm_certificate_arn   = module.edge.acm_certificate_regional_arn

  web_api_image       = var.web_api_image
  etl_worker_image    = var.etl_worker_image
  report_worker_image = var.report_worker_image

  ecs_execution_role_arn   = module.security.ecs_execution_role_arn
  ecs_web_task_role_arn    = module.security.ecs_web_task_role_arn
  ecs_etl_task_role_arn    = module.security.ecs_etl_task_role_arn
  ecs_report_task_role_arn = module.security.ecs_report_task_role_arn

  ecs_web_security_group_id    = module.networking.ecs_web_security_group_id
  ecs_etl_security_group_id    = module.networking.ecs_etl_security_group_id
  ecs_report_security_group_id = module.networking.ecs_report_security_group_id

  aurora_writer_endpoint = module.database.aurora_writer_endpoint
  aurora_reader_endpoint = module.database.aurora_reader_endpoint
  aurora_port            = module.database.aurora_port
  redis_endpoint         = module.database.redis_primary_endpoint
  redis_port             = module.database.redis_port

  sqs_etl_queue_url    = module.messaging.sqs_etl_queue_url
  sqs_report_queue_url = module.messaging.sqs_report_queue_url

  s3_raw_bucket_name     = module.storage.s3_raw_bucket_name
  s3_reports_bucket_name = module.storage.s3_reports_bucket_name

  db_secret_arn = module.database.db_secret_arn

  web_min_capacity    = var.web_min_capacity
  web_max_capacity    = var.web_max_capacity
  etl_min_capacity    = var.etl_min_capacity
  etl_max_capacity    = var.etl_max_capacity
  report_min_capacity = var.report_min_capacity
  report_max_capacity = var.report_max_capacity

  sqs_etl_queue_name    = module.messaging.sqs_etl_queue_name
  sqs_report_queue_name = module.messaging.sqs_report_queue_name
}

# ─────────────────────────────────────────────────────────
# 7. EDGE
# ─────────────────────────────────────────────────────────
module "edge" {
  source = "./modules/edge"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name_prefix      = local.name_prefix
  domain_name      = var.domain_name
  hosted_zone_name = var.hosted_zone_name

  alb_dns_name = module.compute.alb_dns_name
  alb_zone_id  = module.compute.alb_zone_id
  s3_reports_bucket_regional_domain = module.storage.s3_reports_bucket_regional_domain

  waf_web_acl_arn = module.security.waf_web_acl_arn
}

# ─────────────────────────────────────────────────────────
# 8. OBSERVABILITY
# ─────────────────────────────────────────────────────────
module "observability" {
  source = "./modules/observability"

  name_prefix = local.name_prefix
  aws_region = var.aws_region
  alert_email = var.alert_email

  ecs_cluster_name     = module.compute.ecs_cluster_name
  ecs_web_service_name = module.compute.ecs_web_service_name
  ecs_etl_service_name = module.compute.ecs_etl_service_name
  ecs_rep_service_name = module.compute.ecs_rep_service_name

  alb_arn_suffix          = module.compute.alb_arn_suffix
  alb_target_group_suffix = module.compute.alb_target_group_arn_suffix

  aurora_cluster_id       = module.database.aurora_cluster_id
  redis_replication_group = module.database.redis_replication_group_id

  sqs_etl_queue_name    = module.messaging.sqs_etl_queue_name
  sqs_etl_dlq_name      = module.messaging.sqs_etl_dlq_name
  sqs_report_queue_name = module.messaging.sqs_report_queue_name
  sqs_report_dlq_name   = module.messaging.sqs_report_dlq_name

  vpc_id = module.networking.vpc_id
}