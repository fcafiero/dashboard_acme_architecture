variable "name_prefix" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "sqs_etl_queue_arn" {
  type = string
}

# Aggiunto per CORS dinamico
variable "domain_name" {
  description = "Dominio della dashboard per CORS configuration"
  type        = string
}