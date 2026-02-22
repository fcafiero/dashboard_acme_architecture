output "kms_key_arn" {
  description = "ARN della KMS CMK"
  value       = aws_kms_key.main.arn
}

output "kms_key_id" {
  description = "ID della KMS CMK"
  value       = aws_kms_key.main.key_id
}

output "ecs_execution_role_arn" {
  description = "ARN dell'ECS Execution Role"
  value       = aws_iam_role.ecs_execution.arn
}

output "ecs_web_task_role_arn" {
  description = "ARN del Web/API Task Role"
  value       = aws_iam_role.ecs_web_task.arn
}

output "ecs_etl_task_role_arn" {
  description = "ARN dell'ETL Task Role"
  value       = aws_iam_role.ecs_etl_task.arn
}

output "ecs_report_task_role_arn" {
  description = "ARN del Report Task Role"
  value       = aws_iam_role.ecs_report_task.arn
}

output "waf_web_acl_arn" {
  description = "ARN del WAF WebACL per CloudFront"
  value       = aws_wafv2_web_acl.cloudfront.arn
}