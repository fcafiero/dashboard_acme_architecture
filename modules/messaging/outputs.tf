output "sqs_etl_queue_arn" {
  value = aws_sqs_queue.etl.arn
}

output "sqs_etl_queue_url" {
  value = aws_sqs_queue.etl.url
}

output "sqs_etl_queue_name" {
  value = aws_sqs_queue.etl.name
}

output "sqs_etl_dlq_name" {
  value = aws_sqs_queue.etl_dlq.name
}

output "sqs_report_queue_arn" {
  value = aws_sqs_queue.report.arn
}

output "sqs_report_queue_url" {
  value = aws_sqs_queue.report.url
}

output "sqs_report_queue_name" {
  value = aws_sqs_queue.report.name
}

output "sqs_report_dlq_name" {
  value = aws_sqs_queue.report_dlq.name
}