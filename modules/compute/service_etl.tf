# ═══════════════════════════════════════════════════════════
# SERVICE 2: ETL WORKERS
# ═══════════════════════════════════════════════════════════
# - Poll SQS ETL Queue, elabora file da S3, scrive su Aurora
# - Scale-to-zero quando la coda è vuota
# - Fargate SPOT per ridurre costi (workload interrompibile)
# - CPU e memoria maggiori per il processing pesante
# ═══════════════════════════════════════════════════════════

resource "aws_cloudwatch_log_group" "etl_worker" {
  name              = "/aws/ecs/${var.name_prefix}/etl-worker"
  retention_in_days = 30

  tags = {
    Name    = "${var.name_prefix}-etl-worker-logs"
    Service = "etl-worker"
  }
}

resource "aws_ecs_task_definition" "etl_worker" {
  family                   = "${var.name_prefix}-etl-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 4096  # 4 vCPU — processing pesante
  memory                   = 8192  # 8 GB — file streaming
  execution_role_arn       = var.ecs_execution_role_arn
  task_role_arn            = var.ecs_etl_task_role_arn

  container_definitions = jsonencode([
    {
      name      = "etl-worker"
      image     = var.etl_worker_image != "" ? var.etl_worker_image : "${aws_ecr_repository.etl_worker.repository_url}:latest"
      essential = true

      environment = [
        { name = "APP_ENV", value = "production" },
        { name = "WORKER_TYPE", value = "etl" },
        { name = "DB_HOST_WRITE", value = var.aurora_writer_endpoint },
        { name = "DB_PORT", value = tostring(var.aurora_port) },
        { name = "DB_NAME", value = "acme_dashboard" },
        { name = "REDIS_HOST", value = var.redis_endpoint },
        { name = "REDIS_PORT", value = tostring(var.redis_port) },
        { name = "SQS_QUEUE_URL", value = var.sqs_etl_queue_url },
        { name = "S3_RAW_BUCKET", value = var.s3_raw_bucket_name },
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
          "awslogs-group"         = aws_cloudwatch_log_group.etl_worker.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "etl"
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
          "awslogs-group"         = aws_cloudwatch_log_group.etl_worker.name
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
    Name    = "${var.name_prefix}-etl-worker-task"
    Service = "etl-worker"
  }
}

resource "aws_ecs_service" "etl_worker" {
  name            = "${var.name_prefix}-etl-worker"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.etl_worker.arn
  desired_count   = var.etl_min_capacity

  # Fargate SPOT per efficienza economica
  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 4 # 80% delle task su Spot
    base              = 0
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1 # 20% su on-demand come baseline
    base              = 0
  }

  deployment_minimum_healthy_percent = 0   # Scale-to-zero compatibile
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_etl_security_group_id]
    assign_public_ip = false
  }

  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  tags = {
    Name    = "${var.name_prefix}-etl-worker-service"
    Service = "etl-worker"
  }

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }
}