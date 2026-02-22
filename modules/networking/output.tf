# ═══════════════════════════════════════════════════════════
# VPC — Rete principale con subnet pubbliche e private
# ═══════════════════════════════════════════════════════════
#
# Architettura di rete:
# ┌─────────────────────────────────────────────────────┐
# │ VPC 10.0.0.0/16                                     │
# │                                                     │
# │  ┌─── AZ-a ────────┐   ┌─── AZ-b ────────┐        │
# │  │ Public  /24      │   │ Public  /24      │        │
# │  │ (ALB, NAT GW)    │   │ (ALB, NAT GW)    │        │
# │  │                  │   │                  │        │
# │  │ Private App /22  │   │ Private App /22  │        │
# │  │ (Fargate Tasks)  │   │ (Fargate Tasks)  │        │
# │  │                  │   │                  │        │
# │  │ Private DB  /24  │   │ Private DB  /24  │        │
# │  │ (Aurora, Redis)  │   │ (Aurora, Redis)  │        │
# │  └─────────────────┘   └─────────────────┘        │
# └─────────────────────────────────────────────────────┘
# ═══════════════════════════════════════════════════════════

# ── VPC ──────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

# ── INTERNET GATEWAY ────────────────────────────────────

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

# ── SUBNETS ─────────────────────────────────────────────

# Public Subnets — ALB, NAT Gateway
resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index) # /24
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name_prefix}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  }
}

# Private App Subnets — Fargate Tasks (larger /22 per more IPs for ENIs)
resource "aws_subnet" "private_app" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 6, count.index + 4) # /22 — 1022 IPs each
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.name_prefix}-private-app-${var.availability_zones[count.index]}"
    Tier = "private-app"
  }
}

# Private Database Subnets — Aurora, Redis
resource "aws_subnet" "private_db" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10) # /24
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.name_prefix}-private-db-${var.availability_zones[count.index]}"
    Tier = "private-db"
  }
}

# ── NAT GATEWAYS (uno per AZ per resilienza) ────────────

resource "aws_eip" "nat" {
  count  = length(var.availability_zones)
  domain = "vpc"

  tags = {
    Name = "${var.name_prefix}-nat-eip-${var.availability_zones[count.index]}"
  }
}

resource "aws_nat_gateway" "main" {
  count = length(var.availability_zones)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.name_prefix}-nat-${var.availability_zones[count.index]}"
  }

  depends_on = [aws_internet_gateway.main]
}

# ── ROUTE TABLES ────────────────────────────────────────

# Route table pubblica — traffico verso Internet via IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.name_prefix}-rt-public"
  }
}

resource "aws_route_table_association" "public" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route tables private — una per AZ, traffico verso Internet via NAT GW
resource "aws_route_table" "private" {
  count = length(var.availability_zones)

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name = "${var.name_prefix}-rt-private-${var.availability_zones[count.index]}"
  }
}

resource "aws_route_table_association" "private_app" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route_table_association" "private_db" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ── SECURITY GROUPS ─────────────────────────────────────

# ALB Security Group
resource "aws_security_group" "alb" {
  name_prefix = "${var.name_prefix}-alb-"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from CloudFront"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    # CloudFront usa l'AWS managed prefix list
    # In produzione, restringere agli IP CloudFront
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound to VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.name_prefix}-alb-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ECS Web/API Security Group
resource "aws_security_group" "ecs_web" {
  name_prefix = "${var.name_prefix}-ecs-web-"
  description = "Security group for Web/API Fargate tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-ecs-web-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ECS ETL Worker Security Group
resource "aws_security_group" "ecs_etl" {
  name_prefix = "${var.name_prefix}-ecs-etl-"
  description = "Security group for ETL Worker Fargate tasks"
  vpc_id      = aws_vpc.main.id

  # No ingress — ETL workers solo poll SQS (outbound)

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-ecs-etl-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ECS Report Worker Security Group
resource "aws_security_group" "ecs_report" {
  name_prefix = "${var.name_prefix}-ecs-report-"
  description = "Security group for Report Worker Fargate tasks"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-ecs-report-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Aurora Security Group
resource "aws_security_group" "aurora" {
  name_prefix = "${var.name_prefix}-aurora-"
  description = "Security group for Aurora PostgreSQL cluster"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "PostgreSQL from Web/API tasks"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [
      aws_security_group.ecs_web.id,
      aws_security_group.ecs_etl.id,
      aws_security_group.ecs_report.id,
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-aurora-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Redis Security Group
resource "aws_security_group" "redis" {
  name_prefix = "${var.name_prefix}-redis-"
  description = "Security group for ElastiCache Redis"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Redis from Web/API and workers"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    security_groups = [
      aws_security_group.ecs_web.id,
      aws_security_group.ecs_etl.id,
      aws_security_group.ecs_report.id,
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-redis-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# VPC Endpoints Security Group
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.name_prefix}-vpce-"
  description = "Security group for VPC Endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from private subnets"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.name_prefix}-vpce-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── VPC FLOW LOGS ───────────────────────────────────────

resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.flow_log.arn
  log_destination = aws_cloudwatch_log_group.flow_log.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-vpc-flow-log"
  }
}

resource "aws_cloudwatch_log_group" "flow_log" {
  name              = "/aws/vpc/flow-log/${var.name_prefix}"
  retention_in_days = 30

  tags = {
    Name = "${var.name_prefix}-vpc-flow-log"
  }
}

resource "aws_iam_role" "flow_log" {
  name_prefix = "${var.name_prefix}-flow-log-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "flow_log" {
  name_prefix = "flow-log-"
  role        = aws_iam_role.flow_log.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "*"
    }]
  })
}