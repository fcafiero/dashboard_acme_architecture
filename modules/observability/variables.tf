variable "name_prefix" {
  type = string
}

# Aggiunto: region per i widget della dashboard
variable "aws_region" {
  description = "AWS Region per i widget CloudWatch"
  type        = string
}

variable "alert_email" {
  type = string
}

variable "ecs_cluster_name" {
  type = string
}

variable "ecs_web_service_name" {
  type = string
}

variable "ecs_etl_service_name" {
  type = string
}

variable "ecs_rep_service_name" {
  type = string
}

variable "alb_arn_suffix" {
  type = string
}

variable "alb_target_group_suffix" {
  type = string
}

variable "aurora_cluster_id" {
  type = string
}

variable "redis_replication_group" {
  type = string
}

variable "sqs_etl_queue_name" {
  type = string
}

variable "sqs_etl_dlq_name" {
  type = string
}

variable "sqs_report_queue_name" {
  type = string
}

variable "sqs_report_dlq_name" {
  type = string
}

variable "vpc_id" {
  type = string
}