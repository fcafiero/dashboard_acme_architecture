variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "database_subnet_ids" {
  type = list(string)
}

variable "aurora_instance_class" {
  type = string
}

variable "aurora_security_group_id" {
  type = string
}

variable "aurora_min_reader_count" {
  type    = number
  default = 1
}

variable "aurora_max_reader_count" {
  type    = number
  default = 5
}

variable "kms_key_arn" {
  type = string
}

variable "redis_node_type" {
  type = string
}

variable "redis_security_group_id" {
  type = string
}

variable "redis_subnet_ids" {
  type = list(string)
}