variable "name_prefix" {
  description = "Prefisso per i nomi delle risorse"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block per la VPC"
  type        = string
}

variable "availability_zones" {
  description = "Lista delle Availability Zones"
  type        = list(string)
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
}