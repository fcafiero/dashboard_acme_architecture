# ═══════════════════════════════════════════════════════════
# AUTO SCALING — Policies per ogni servizio ECS
# ═══════════════════════════════════════════════════════════

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# WEB/API — Target Tracking su CPU + ALB Request Count
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

resource "aws_appautoscaling_target" "web_api" {
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.web_api.name}"
  min_capacity       = var.web_min_capacity
  max_capacity       = var.web_max_capacity
}

# Policy 1: CPU Target Tracking
resource "aws_appautoscaling_policy" "web_api_cpu" {
  name               = "${var.name_prefix}-web-api-cpu-scaling"
  service_namespace  = aws_appautoscaling_target.web_api.service_namespace
  scalable_dimension = aws_appautoscaling_target.web_api.scalable_dimension
  resource_id        = aws_appautoscaling_target.web_api.resource_id
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 60.0
    scale_in_cooldown  = 300 # 5 min — evita flapping
    scale_out_cooldown = 60  # 1 min — reazione rapida
  }
}

# Policy 2: ALB Request Count per Target
resource "aws_appautoscaling_policy" "web_api_requests" {
  name               = "${var.name_prefix}-web-api-request-scaling"
  service_namespace  = aws_appautoscaling_target.web_api.service_namespace
  scalable_dimension = aws_appautoscaling_target.web_api.scalable_dimension
  resource_id        = aws_appautoscaling_target.web_api.resource_id
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.main.arn_suffix}/${aws_lb_target_group.web_api.arn_suffix}"
    }
    target_value       = 500 # 500 req/min per target
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ETL WORKERS — Step Scaling su SQS Queue Depth
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

resource "aws_appautoscaling_target" "etl_worker" {
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.etl_worker.name}"
  min_capacity       = var.etl_min_capacity
  max_capacity       = var.etl_max_capacity
}

# Scale OUT quando ci sono messaggi in coda
resource "aws_appautoscaling_policy" "etl_scale_out" {
  name               = "${var.name_prefix}-etl-scale-out"
  service_namespace  = aws_appautoscaling_target.etl_worker.service_namespace
  scalable_dimension = aws_appautoscaling_target.etl_worker.scalable_dimension
  resource_id        = aws_appautoscaling_target.etl_worker.resource_id
  policy_type        = "StepScaling"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 120
    metric_aggregation_type = "Maximum"

    # 1-5 messaggi → +2 tasks
    step_adjustment {
      metric_interval_lower_bound = 0
      metric_interval_upper_bound = 5
      scaling_adjustment          = 2
    }

    # 5-20 messaggi → +5 tasks
    step_adjustment {
      metric_interval_lower_bound = 5
      metric_interval_upper_bound = 20
      scaling_adjustment          = 5
    }

    # >20 messaggi → +10 tasks
    step_adjustment {
      metric_interval_lower_bound = 20
      scaling_adjustment          = 10
    }
  }
}

# Scale IN quando la coda è vuota
resource "aws_appautoscaling_policy" "etl_scale_in" {
  name               = "${var.name_prefix}-etl-scale-in"
  service_namespace  = aws_appautoscaling_target.etl_worker.service_namespace
  scalable_dimension = aws_appautoscaling_target.etl_worker.scalable_dimension
  resource_id        = aws_appautoscaling_target.etl_worker.resource_id
  policy_type        = "StepScaling"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 300
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }
}

# CloudWatch Alarm per triggerare lo scaling ETL
resource "aws_cloudwatch_metric_alarm" "etl_queue_depth_high" {
  alarm_name          = "${var.name_prefix}-etl-queue-depth-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0

  dimensions = {
    QueueName = var.sqs_etl_queue_name
  }

  alarm_actions = [aws_appautoscaling_policy.etl_scale_out.arn]
}

resource "aws_cloudwatch_metric_alarm" "etl_queue_depth_low" {
  alarm_name          = "${var.name_prefix}-etl-queue-depth-low"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 5 # 5 minuti a zero prima di scalare in giù
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0

  dimensions = {
    QueueName = var.sqs_etl_queue_name
  }

  alarm_actions = [aws_appautoscaling_policy.etl_scale_in.arn]
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# REPORT WORKERS — Step Scaling su SQS Queue Depth
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

resource "aws_appautoscaling_target" "report_worker" {
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.report_worker.name}"
  min_capacity       = var.report_min_capacity
  max_capacity       = var.report_max_capacity
}

resource "aws_appautoscaling_policy" "report_scale_out" {
  name               = "${var.name_prefix}-report-scale-out"
  service_namespace  = aws_appautoscaling_target.report_worker.service_namespace
  scalable_dimension = aws_appautoscaling_target.report_worker.scalable_dimension
  resource_id        = aws_appautoscaling_target.report_worker.resource_id
  policy_type        = "StepScaling"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 120
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      metric_interval_upper_bound = 5
      scaling_adjustment          = 2
    }

    step_adjustment {
      metric_interval_lower_bound = 5
      scaling_adjustment          = 5
    }
  }
}

resource "aws_appautoscaling_policy" "report_scale_in" {
  name               = "${var.name_prefix}-report-scale-in"
  service_namespace  = aws_appautoscaling_target.report_worker.service_namespace
  scalable_dimension = aws_appautoscaling_target.report_worker.scalable_dimension
  resource_id        = aws_appautoscaling_target.report_worker.resource_id
  policy_type        = "StepScaling"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 300
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "report_queue_depth_high" {
  alarm_name          = "${var.name_prefix}-report-queue-depth-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0

  dimensions = {
    QueueName = var.sqs_report_queue_name
  }

  alarm_actions = [aws_appautoscaling_policy.report_scale_out.arn]
}

resource "aws_cloudwatch_metric_alarm" "report_queue_depth_low" {
  alarm_name          = "${var.name_prefix}-report-queue-depth-low"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 5
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0

  dimensions = {
    QueueName = var.sqs_report_queue_name
  }

  alarm_actions = [aws_appautoscaling_policy.report_scale_in.arn]
}