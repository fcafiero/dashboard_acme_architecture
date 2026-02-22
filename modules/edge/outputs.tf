output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.main.id
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.main.domain_name
}

output "acm_certificate_cloudfront_arn" {
  value = aws_acm_certificate.cloudfront.arn
}

output "acm_certificate_regional_arn" {
  value = aws_acm_certificate.alb.arn
}