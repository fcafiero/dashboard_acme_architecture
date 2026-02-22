# ═══════════════════════════════════════════════════════════
# OUTPUT PRINCIPALI
# ═══════════════════════════════════════════════════════════

output "deployment_region" {
  description = "Region AWS in cui è deployata l'infrastruttura"
  value       = var.aws_region
}

output "availability_zones" {
  description = "Availability Zones utilizzate"
  value       = local.resolved_azs
}

output "dashboard_url" {
  description = "URL della dashboard"
  value       = "https://${var.domain_name}"
}

output "cloudfront_distribution_id" {
  description = "ID della distribuzione CloudFront"
  value       = module.edge.cloudfront_distribution_id
}

output "alb_dns_name" {
  description = "DNS name dell'ALB"
  value       = module.compute.alb_dns_name
}

output "aurora_writer_endpoint" {
  description = "Endpoint Aurora Writer"
  value       = module.database.aurora_writer_endpoint
  sensitive   = true
}

output "aurora_reader_endpoint" {
  description = "Endpoint Aurora Reader"
  value       = module.database.aurora_reader_endpoint
  sensitive   = true
}

output "s3_raw_bucket" {
  description = "Nome del bucket S3 per i dati raw"
  value       = module.storage.s3_raw_bucket_name
}

output "ecr_repository_urls" {
  description = "URL dei repository ECR"
  value       = module.compute.ecr_repository_urls
}

output "ecs_cluster_name" {
  description = "Nome del cluster ECS"
  value       = module.compute.ecs_cluster_name
}