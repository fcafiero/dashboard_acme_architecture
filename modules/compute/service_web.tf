# ═══════════════════════════════════════════════════════════
# SERVICE 1: WEB DASHBOARD & API
# ═══════════════════════════════════════════════════════════
# - Dietro ALB, serve la dashboard e le API REST
# - Min 2 task (Multi-AZ), Max 10
# - Scala su CPU e ALB request count
# ═══════════════════════════════════════════════════════════

resource "aws_cloudwatch_log_group" "web_api" {
  name              = "/aws/ecs/${var.name_prefix}/web-api"
  retention_in_days = 30

  tags = {
    Name    = "${var.name_prefix}-web-api-logs"
    Service = "web-api"
  }
}

resource "aws_ecs_task_definition" "web_api" {
  family                   = "${var.name_prefix}-web-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024 # 1 vCPU
  memory                   = 2048 # 2 GB
  execution_role_arn       = var.ecs_execution_role_arn
  task_role_arn            = var.ecs_web_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "web-api"
      image     = var.web_api_image != "" ? var.web_api_image : "${aws_ecr_repository.web_api.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "APP_ENV", value = "production" },
        { name = "PORT", value = "8080" },
        { name = "DB_HOST_READ", value = var.aurora_reader_endpoint },
        { name = "DB_HOST_WRITE", value = var.aurora_writer_endpoint },
        { name = "DB_PORT", value = tostring(var.aurora_port) },
        { name = "DB_NAME", value = "acme_dashboard" },
        { name = "REDIS_HOST", value = var.redis_endpoint },
        { name = "REDIS_PORT", value = tostring(var.redis_port) },
        { name = "SQS_REPORT_QUEUE_URL", value = var.sqs_report_queue_url },
        { name = "S3_RAW_BUCKET", value = var.s3_raw_bucket_name },
        { name = "S3_REPORTS_BUCKET", value = var.s3_reports_bucket_name },
        { name = "AWS_REGION", value = var.aws_region },
      ]

      secrets = [
        {
          name      = "DB_CREDENTIALS"
          valueFrom = var.db_secret_arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.web_api.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "web-api"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    },
    # X-Ray sidecar per distributed tracing
    {
      name      = "xray-daemon"
      image     = "public.ecr.aws/xray/aws-xray-daemon:latest"
      essential = false

      portMappings = [
        {
          containerPort = 2000
          protocol      = "udp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.web_api.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "xray"
        }
      }

      cpu    = 32
      memory = 256
    }
  ])

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64" # Graviton — migliore rapporto prezzo/performance
  }

  tags = {
    Name    = "${var.name_prefix}-web-api-task"
    Service = "web-api"
  }
}

resource "aws_ecs_service" "web_api" {
  name            = "${var.name_prefix}-web-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.web_api.arn
  desired_count   = var.web_min_capacity
  launch_type     = "FARGATE"

  # Deployment
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 120

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_web_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web_api.arn
    container_name   = "web-api"
    container_port   = 8080
  }

  # Distribuire task su AZ diverse
  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  # Prevenire race condition col target group
  depends_on = [aws_lb_listener.https]

  tags = {
    Name    = "${var.name_prefix}-web-api-service"
    Service = "web-api"
  }

  lifecycle {
    ignore_changes = [desired_count, task_definition] # Gestiti da auto-scaling e CI/CD
  }
}