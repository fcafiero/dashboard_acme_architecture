# ═══════════════════════════════════════════════════════════
# ECS CLUSTER + ECR REPOSITORIES + ALB
# ═══════════════════════════════════════════════════════════

# ── ECS Cluster ─────────────────────────────────────────
resource "aws_ecs_cluster" "main" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  configuration {
    execute_command_configuration {
      logging = "OVERRIDE"

      log_configuration {
        cloud_watch_log_group_name = aws_cloudwatch_log_group.ecs_exec.name
      }
    }
  }

  tags = {
    Name = "${var.name_prefix}-ecs-cluster"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

resource "aws_cloudwatch_log_group" "ecs_exec" {
  name              = "/aws/ecs/${var.name_prefix}/exec"
  retention_in_days = 30
}

# ── ECR Repositories ───────────────────────────────────
resource "aws_ecr_repository" "web_api" {
  name                 = "${var.name_prefix}/web-api"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }

  tags = {
    Name = "${var.name_prefix}-web-api"
  }
}

resource "aws_ecr_repository" "etl_worker" {
  name                 = "${var.name_prefix}/etl-worker"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }

  tags = {
    Name = "${var.name_prefix}-etl-worker"
  }
}

resource "aws_ecr_repository" "report_worker" {
  name                 = "${var.name_prefix}/report-worker"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }

  tags = {
    Name = "${var.name_prefix}-report-worker"
  }
}

# Lifecycle policy per pulizia immagini vecchie
resource "aws_ecr_lifecycle_policy" "cleanup" {
  for_each = {
    web_api       = aws_ecr_repository.web_api.name
    etl_worker    = aws_ecr_repository.etl_worker.name
    report_worker = aws_ecr_repository.report_worker.name
  }

  repository = each.value

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 20 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# ── APPLICATION LOAD BALANCER ───────────────────────────
resource "aws_lb" "main" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = true
  enable_http2               = true
  drop_invalid_header_fields = true

  access_logs {
    bucket  = "" # Configurare con bucket dedicato per ALB logs
    enabled = false
  }

  tags = {
    Name = "${var.name_prefix}-alb"
  }
}

# ── ALB Target Group per Web/API ────────────────────────
resource "aws_lb_target_group" "web_api" {
  name_prefix = "web-"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Fargate usa awsvpc, quindi target type = ip

  health_check {
    enabled             = true
    interval            = 30
    path                = "/health"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 10
    matcher             = "200"
  }

  deregistration_delay = 30 # Drain connections rapidamente per rolling deploy

  stickiness {
    type    = "lb_cookie"
    enabled = false # Sessioni in Redis, no sticky sessions
  }

  tags = {
    Name = "${var.name_prefix}-web-api-tg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── ALB Listener HTTPS ──────────────────────────────────
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_api.arn
  }
}

# Redirect HTTP → HTTPS
resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}