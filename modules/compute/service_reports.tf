# ═══════════════════════════════════════════════════════════
# SERVICE 3: REPORT WORKERS
# ═══════════════════════════════════════════════════════════
# - Poll SQS Report Queue, genera PDF, salva su S3, email via SES
# - Scale-to-zero quando la coda è vuota
# - Fargate standard (non Spot) per completamento predicibile
# ═══════════════════════════════════════════════════════════

resource "aws_cloudwatch_log_group" "report_worker" {
  name              = "/aws/ecs/${var.name_prefix}/report-worker"
  retention_in_days = 30

  tags = {
    Name    = "${var.name_prefix}-report-worker-logs"
    Service = "report-worker"
  }
}

resource "aws_ecs_task_definition" "report_worker" {
  family                   = "${var.name_prefix}-report-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 2048 # 2 vCPU
  memory                   = 4096 # 4 GB — PDF generation
  execution_role_arn       = var.ecs_execution_role_arn
  task_role_arn            = var.ecs_report_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "report-worker"
      image     = var.report_worker_image != "" ? var.report_worker_image : "${aws_ecr_repository.report_worker.repository_url}:latest"
      essential = true

      environment = [
        { name = "APP_ENV", value = "production" },
        { name = "WORKER_TYPE", value = "report" },
        { name = "DB_HOST_READ", value = var.aurora_reader_endpoint },
        { name = "DB_PORT", value = tostring(var.aurora_port) },
        { name = "DB_NAME", value = "acme_dashboard" },
        { name = "REDIS_HOST", value = var.redis_endpoint },
        { name = "REDIS_PORT", value = tostring(var.redis_port) },
        { name = "SQS_QUEUE_URL", value = var.sqs_report_queue_url },
        { name = "S3_REPORTS_BUCKET", value = var.s3_reports_bucket_name },
        { name = "AWS_REGION", value = var.aws_region },
        { name = "SES_FROM_ADDRESS", value = "noreply@acme.com" },
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
          "awslogs-group"         = aws_cloudwatch_log_group.report_worker.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "report"
        }
      }
    },
    {
      name      = "xray-daemon"
      image     = "public.ecr.aws/xray/aws-xray-daemon:latest"
      essential = false

      portMappings = [{
        containerPort = 2000
        protocol      = "udp"
      }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.report_worker.name
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
    cpu_architecture        = "ARM64"
  }

  tags = {
    Name    = "${var.name_prefix}-report-worker-task"
    Service = "report-worker"
  }
}

resource "aws_ecs_service" "report_worker" {
  name            = "${var.name_prefix}-report-worker"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.report_worker.arn
  desired_count   = var.report_min_capacity
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_report_security_group_id]
    assign_public_ip = false
  }

  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  tags = {
    Name    = "${var.name_prefix}-report-worker-service"
    Service = "report-worker"
  }

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }
}