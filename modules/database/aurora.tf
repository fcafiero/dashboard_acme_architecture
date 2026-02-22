# ═══════════════════════════════════════════════════════════
# AURORA POSTGRESQL — Writer + Auto-Scaling Reader Replicas
# ═══════════════════════════════════════════════════════════

# ── Subnet Group ────────────────────────────────────────
resource "aws_db_subnet_group" "aurora" {
  name       = "${var.name_prefix}-aurora"
  subnet_ids = var.database_subnet_ids

  tags = merge(local.db_tags, {
    Name = "${var.name_prefix}-aurora-subnet-group"
  })
}

# ── Parameter Group ─────────────────────────────────────
resource "aws_rds_cluster_parameter_group" "aurora" {
  name_prefix = "${var.name_prefix}-aurora-"
  family      = local.aurora_family
  description = "Custom parameter group for ${var.name_prefix}"

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  tags = merge(local.db_tags, {
    Name = "${var.name_prefix}-aurora-params"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ── Credenziali DB in Secrets Manager ───────────────────
resource "random_password" "aurora_master" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}|:,.<>?"
}

resource "aws_secretsmanager_secret" "aurora" {
  name_prefix = "${var.name_prefix}/aurora/"
  description = "Aurora PostgreSQL master credentials"
  kms_key_id  = var.kms_key_arn

  tags = merge(local.db_tags, {
    Name = "${var.name_prefix}-aurora-secret"
  })
}

resource "aws_secretsmanager_secret_version" "aurora" {
  secret_id = aws_secretsmanager_secret.aurora.id

  secret_string = jsonencode({
    username = local.aurora_master_user
    password = random_password.aurora_master.result
    engine   = "postgres"
    host     = aws_rds_cluster.main.endpoint
    port     = aws_rds_cluster.main.port
    dbname   = local.aurora_database_name
  })
}

# ── Aurora Cluster ──────────────────────────────────────
resource "aws_rds_cluster" "main" {
  cluster_identifier = "${var.name_prefix}-aurora"

  engine         = local.aurora_engine
  engine_version = local.aurora_engine_version
  engine_mode    = "provisioned"

  database_name   = local.aurora_database_name
  master_username = local.aurora_master_user
  master_password = random_password.aurora_master.result
  port            = local.aurora_port

  # Rete & Security
  db_subnet_group_name            = aws_db_subnet_group.aurora.name
  vpc_security_group_ids          = [var.aurora_security_group_id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name

  # Encryption
  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  # Backup
  backup_retention_period      = 14
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"

  # Protection
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name_prefix}-aurora-final-snapshot"
  copy_tags_to_snapshot     = true

  # Monitoring
  enabled_cloudwatch_logs_exports = ["postgresql"]

  # IAM Auth
  iam_database_authentication_enabled = true

  tags = merge(local.db_tags, {
    Name = "${var.name_prefix}-aurora-cluster"
  })

  lifecycle {
    ignore_changes = [master_password]
  }
}

# ── Writer Instance ─────────────────────────────────────
resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${var.name_prefix}-aurora-writer"
  cluster_identifier = aws_rds_cluster.main.id

  engine         = aws_rds_cluster.main.engine
  engine_version = aws_rds_cluster.main.engine_version
  instance_class = var.aurora_instance_class

  publicly_accessible  = false
  db_subnet_group_name = aws_db_subnet_group.aurora.name

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.aurora_monitoring.arn

  performance_insights_enabled    = true
  performance_insights_kms_key_id = var.kms_key_arn

  tags = merge(local.db_tags, {
    Name = "${var.name_prefix}-aurora-writer"
    Role = "writer"
  })
}

# ── Reader Instances ────────────────────────────────────
resource "aws_rds_cluster_instance" "reader" {
  count = var.aurora_min_reader_count

  identifier         = "${var.name_prefix}-aurora-reader-${count.index}"
  cluster_identifier = aws_rds_cluster.main.id

  engine         = aws_rds_cluster.main.engine
  engine_version = aws_rds_cluster.main.engine_version
  instance_class = var.aurora_instance_class

  publicly_accessible  = false
  db_subnet_group_name = aws_db_subnet_group.aurora.name

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.aurora_monitoring.arn

  performance_insights_enabled    = true
  performance_insights_kms_key_id = var.kms_key_arn

  tags = merge(local.db_tags, {
    Name = "${var.name_prefix}-aurora-reader-${count.index}"
    Role = "reader"
  })
}

# ── Auto-scaling Reader Replicas ────────────────────────
resource "aws_appautoscaling_target" "aurora_readers" {
  service_namespace  = "rds"
  scalable_dimension = "rds:cluster:ReadReplicaCount"
  resource_id        = "cluster:${aws_rds_cluster.main.id}"
  min_capacity       = var.aurora_min_reader_count
  max_capacity       = var.aurora_max_reader_count
}

resource "aws_appautoscaling_policy" "aurora_readers_cpu" {
  name               = "${var.name_prefix}-aurora-reader-cpu-scaling"
  service_namespace  = aws_appautoscaling_target.aurora_readers.service_namespace
  scalable_dimension = aws_appautoscaling_target.aurora_readers.scalable_dimension
  resource_id        = aws_appautoscaling_target.aurora_readers.resource_id
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "RDSReaderAverageCPUUtilization"
    }
    target_value       = 60.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
  }
}

# ── IAM Role per Enhanced Monitoring ────────────────────
resource "aws_iam_role" "aurora_monitoring" {
  name_prefix = "${var.name_prefix}-aurora-mon-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
    }]
  })

  tags = merge(local.db_tags, {
    Name = "${var.name_prefix}-aurora-monitoring-role"
  })
}

resource "aws_iam_role_policy_attachment" "aurora_monitoring" {
  role       = aws_iam_role.aurora_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}