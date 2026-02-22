output "aurora_cluster_arn" {
  value = aws_rds_cluster.main.arn
}

output "aurora_cluster_id" {
  value = aws_rds_cluster.main.cluster_identifier
}

output "aurora_writer_endpoint" {
  value = aws_rds_cluster.main.endpoint
}

output "aurora_reader_endpoint" {
  value = aws_rds_cluster.main.reader_endpoint
}

output "aurora_port" {
  value = local.aurora_port
}

output "db_secret_arn" {
  value = aws_secretsmanager_secret.aurora.arn
}

output "redis_primary_endpoint" {
  value = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_reader_endpoint" {
  value = aws_elasticache_replication_group.redis.reader_endpoint_address
}

output "redis_port" {
  value = local.redis_port
}

output "redis_replication_group_id" {
  value = aws_elasticache_replication_group.redis.id
}