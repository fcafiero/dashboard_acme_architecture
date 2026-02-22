output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  value = aws_ecs_cluster.main.arn
}

output "ecs_web_service_name" {
  value = aws_ecs_service.web_api.name
}

output "ecs_etl_service_name" {
  value = aws_ecs_service.etl_worker.name
}

output "ecs_rep_service_name" {
  value = aws_ecs_service.report_worker.name
}

output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "alb_zone_id" {
  value = aws_lb.main.zone_id
}

output "alb_arn_suffix" {
  value = aws_lb.main.arn_suffix
}

output "alb_target_group_arn_suffix" {
  value = aws_lb_target_group.web_api.arn_suffix
}

output "ecr_repository_urls" {
  value = {
    web_api       = aws_ecr_repository.web_api.repository_url
    etl_worker    = aws_ecr_repository.etl_worker.repository_url
    report_worker = aws_ecr_repository.report_worker.repository_url
  }
}