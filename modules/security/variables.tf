variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "s3_raw_bucket_arn" {
  type = string
}

variable "s3_reports_bucket_arn" {
  type = string
}

variable "sqs_etl_queue_arn" {
  type = string
}

variable "sqs_report_queue_arn" {
  type = string
}

variable "aurora_cluster_arn" {
  type    = string
  default = ""
}

variable "kms_key_arn" {
  type = string
}

variable "alb_security_group_id" {
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