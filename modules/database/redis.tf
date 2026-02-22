# ═══════════════════════════════════════════════════════════
# ELASTICACHE REDIS — Cache, Sessions, Job Status
# ═══════════════════════════════════════════════════════════

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.name_prefix}-redis"
  subnet_ids = var.redis_subnet_ids

  tags = merge(local.db_tags, {
    Name = "${var.name_prefix}-redis-subnet-group"
  })
}

resource "aws_elasticache_parameter_group" "redis" {
  name = "${var.name_prefix}-redis-"
  family      = local.redis_family
  description = "Custom Redis parameters for ${var.name_prefix}"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  parameter {
    name  = "notify-keyspace-events"
    value = "Ex"
  }

  tags = merge(local.db_tags, {
    Name = "${var.name_prefix}-redis-params"
  })
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${var.name_prefix}-redis"
  description          = "Redis cluster for ${var.name_prefix}"

  node_type            = var.redis_node_type
  num_cache_clusters   = 2
  engine               = local.redis_engine
  engine_version       = local.redis_engine_version
  port                 = local.redis_port
  parameter_group_name = aws_elasticache_parameter_group.redis.name

  # Rete
  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [var.redis_security_group_id]

  # Multi-AZ & Failover
  automatic_failover_enabled = true
  multi_az_enabled           = true

  # Encryption
  at_rest_encryption_enabled = true
  kms_key_id                 = var.kms_key_arn
  transit_encryption_enabled = true

  # Maintenance
  maintenance_window       = "sun:05:00-sun:06:00"
  snapshot_window          = "04:00-05:00"
  snapshot_retention_limit = 7

  tags = merge(local.db_tags, {
    Name = "${var.name_prefix}-redis"
  })

  lifecycle {
    ignore_changes = [num_cache_clusters]
  }
}