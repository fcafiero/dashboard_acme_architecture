variable "name_prefix" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "alb_security_group_id" {
  type = string
}

variable "acm_certificate_arn" {
  type = string
}

variable "web_api_image" {
  type = string
}

variable "etl_worker_image" {
  type = string
}

variable "report_worker_image" {
  type = string
}

variable "ecs_execution_role_arn" {
  type = string
}

variable "ecs_web_task_role_arn" {
  type = string
}

variable "ecs_etl_task_role_arn" {
  type = string
}

variable "ecs_report_task_role_arn" {
  type = string
}

variable "ecs_web_security_group_id" {
  type = string
}

variable "ecs_etl_security_group_id" {
  type = string
}

variable "ecs_report_security_group_id" {
  type = string
}

variable "aurora_writer_endpoint" {
  type = string
}

variable "aurora_reader_endpoint" {
  type = string
}

variable "aurora_port" {
  type = number
}

variable "redis_endpoint" {
  type = string
}

variable "redis_port" {
  type = number
}

variable "sqs_etl_queue_url" {
  type = string
}

variable "sqs_report_queue_url" {
  type = string
}

variable "s3_raw_bucket_name" {
  type = string
}

variable "s3_reports_bucket_name" {
  type = string
}

variable "db_secret_arn" {
  type = string
}

variable "web_min_capacity" {
  type = number
}

variable "web_max_capacity" {
  type = number
}

variable "etl_min_capacity" {
  type = number
}

variable "etl_max_capacity" {
  type = number
}

variable "report_min_capacity" {
  type = number
}

variable "report_max_capacity" {
  type = number
}

variable "sqs_etl_queue_name" {
  type = string
}

variable "sqs_report_queue_name" {
  type = string
}