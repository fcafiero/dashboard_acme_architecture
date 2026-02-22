variable "name_prefix" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "hosted_zone_name" {
  type = string
}

variable "alb_dns_name" {
  type = string
}

variable "alb_zone_id" {
  type = string
}

variable "s3_reports_bucket_regional_domain" {
  type = string
}

variable "waf_web_acl_arn" {
  type = string
}