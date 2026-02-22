output "s3_raw_bucket_name" {
  value = aws_s3_bucket.raw.id
}

output "s3_raw_bucket_arn" {
  value = aws_s3_bucket.raw.arn
}

output "s3_reports_bucket_name" {
  value = aws_s3_bucket.reports.id
}

output "s3_reports_bucket_arn" {
  value = aws_s3_bucket.reports.arn
}

output "s3_reports_bucket_regional_domain" {
  value = aws_s3_bucket.reports.bucket_regional_domain_name
}