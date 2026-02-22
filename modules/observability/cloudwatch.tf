# ═══════════════════════════════════════════════════════════
# CLOUDWATCH — Allarmi e Dashboard
# ═══════════════════════════════════════════════════════════
# Tutti i widget della dashboard usano var.aws_region per
# essere portabili su qualsiasi region.
# ═══════════════════════════════════════════════════════════

# ── DLQ ALARMS ──────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "etl_dlq_messages" {
  alarm_name          = "${var.name_prefix}-etl-dlq-has-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "ETL Dead Letter Queue has messages — files failed processing after 3 attempts"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = var.sqs_etl_dlq_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Name     = "${var.name_prefix}-etl-dlq-alarm"
    Severity = "critical"
  }
}

resource "aws_cloudwatch_metric_alarm" "report_dlq_messages" {
  alarm_name          = "${var.name_prefix}-report-dlq-has-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Report Dead Letter Queue has messages — reports failed generation"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = var.sqs_report_dlq_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Name     = "${var.name_prefix}-report-dlq-alarm"
    Severity = "high"
  }
}

# ── ETL QUEUE AGE ───────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "etl_queue_age" {
  alarm_name          = "${var.name_prefix}-etl-queue-old-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 3600
  alarm_description   = "ETL queue has messages older than 1 hour — possible scaling issue"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = var.sqs_etl_queue_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = {
    Name     = "${var.name_prefix}-etl-queue-age-alarm"
    Severity = "warning"
  }
}

# ── ALB 5xx ERRORS ──────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.name_prefix}-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 50
  alarm_description   = "ALB is returning >50 5xx errors in 5 minutes"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = {
    Name     = "${var.name_prefix}-alb-5xx-alarm"
    Severity = "high"
  }
}

# ── ALB LATENCY ─────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  alarm_name          = "${var.name_prefix}-alb-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  extended_statistic  = "p95"
  threshold           = 2
  alarm_description   = "ALB p95 latency is above 2 seconds"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = {
    Name     = "${var.name_prefix}-alb-latency-alarm"
    Severity = "warning"
  }
}

# ── ECS WEB CPU ─────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "web_cpu_high" {
  alarm_name          = "${var.name_prefix}-web-cpu-critical"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "Web/API service CPU is critically high — auto-scaling may be insufficient"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_web_service_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = {
    Name     = "${var.name_prefix}-web-cpu-alarm"
    Severity = "critical"
  }
}

# ── AURORA CPU ──────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "aurora_cpu_high" {
  alarm_name          = "${var.name_prefix}-aurora-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Aurora cluster CPU is high"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = var.aurora_cluster_id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = {
    Name     = "${var.name_prefix}-aurora-cpu-alarm"
    Severity = "high"
  }
}

# ── AURORA FREE STORAGE ────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "aurora_free_storage" {
  alarm_name          = "${var.name_prefix}-aurora-low-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeLocalStorage"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5368709120
  alarm_description   = "Aurora free local storage is below 5GB"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = var.aurora_cluster_id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = {
    Name     = "${var.name_prefix}-aurora-storage-alarm"
    Severity = "critical"
  }
}

# ── REDIS MEMORY ───────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "redis_memory" {
  alarm_name          = "${var.name_prefix}-redis-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Redis memory usage is above 80%"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ReplicationGroupId = var.redis_replication_group
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = {
    Name     = "${var.name_prefix}-redis-memory-alarm"
    Severity = "high"
  }
}

# ═══════════════════════════════════════════════════════════
# CLOUDWATCH DASHBOARD — Region-aware
# ═══════════════════════════════════════════════════════════
# Tutti i widget usano var.aws_region per la proprietà region,
# rendendo la dashboard funzionante in qualsiasi region.
# ═══════════════════════════════════════════════════════════

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.name_prefix}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# ${var.name_prefix} — Operational Dashboard (${var.aws_region})"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "ALB Request Count & Latency"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum" }],
            [".", "TargetResponseTime", ".", ".", { stat = "p95", yAxis = "right" }]
          ]
          period = 60
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "ECS Services — CPU Utilization"
          region = var.aws_region
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_web_service_name, { label = "Web/API" }],
            [".", ".", ".", ".", ".", var.ecs_etl_service_name, { label = "ETL Worker" }],
            [".", ".", ".", ".", ".", var.ecs_rep_service_name, { label = "Report Worker" }]
          ]
          period = 60
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "ECS Services — Running Task Count"
          region = var.aws_region
          metrics = [
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_web_service_name, { label = "Web/API" }],
            [".", ".", ".", ".", ".", var.ecs_etl_service_name, { label = "ETL Worker" }],
            [".", ".", ".", ".", ".", var.ecs_rep_service_name, { label = "Report Worker" }]
          ]
          period = 60
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "SQS Queue Depth"
          region = var.aws_region
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.sqs_etl_queue_name, { label = "ETL Queue" }],
            [".", ".", ".", var.sqs_report_queue_name, { label = "Report Queue" }],
            [".", ".", ".", var.sqs_etl_dlq_name, { label = "ETL DLQ", color = "#d62728" }],
            [".", ".", ".", var.sqs_report_dlq_name, { label = "Report DLQ", color = "#ff7f0e" }]
          ]
          period = 60
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "Aurora — CPU & Connections"
          region = var.aws_region
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBClusterIdentifier", var.aurora_cluster_id],
            [".", "DatabaseConnections", ".", ".", { yAxis = "right" }]
          ]
          period = 60
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 13
        width  = 12
        height = 6
        properties = {
          title  = "Redis — Memory & Connections"
          region = var.aws_region
          metrics = [
            ["AWS/ElastiCache", "DatabaseMemoryUsagePercentage", "ReplicationGroupId", var.redis_replication_group],
            [".", "CurrConnections", ".", ".", { yAxis = "right" }]
          ]
          period = 60
          view   = "timeSeries"
        }
      }
    ]
  })
}