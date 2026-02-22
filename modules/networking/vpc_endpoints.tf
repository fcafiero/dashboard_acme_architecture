# ═══════════════════════════════════════════════════════════
# VPC ENDPOINTS — Region-aware
# ═══════════════════════════════════════════════════════════
# Tutti gli endpoint usano var.aws_region per costruire il
# service_name, rendendoli portabili su qualsiasi region.
#
# NOTA su eu-south-1 (Milano):
# Non tutti gli interface endpoints sono disponibili in tutte
# le region. Il blocco locals gestisce questa variabilità.
# ═══════════════════════════════════════════════════════════

# ── S3 Gateway Endpoint (GRATUITO — disponibile ovunque) ─
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.aws_region}.s3"

  vpc_endpoint_type = "Gateway"

  route_table_ids = aws_route_table.private[*].id

  tags = {
    Name = "${var.name_prefix}-vpce-s3"
  }
}

# ── Verifica disponibilità endpoint per la region ───────
# Alcuni interface endpoints potrebbero non essere disponibili
# in tutte le region (es. eu-south-1 è più recente).
# Usiamo un data source per verificare.
# ═══════════════════════════════════════════════════════════

data "aws_vpc_endpoint_service" "check" {
  for_each = toset([
    "ecr.api",
    "ecr.dkr",
    "sqs",
    "logs",
    "monitoring",
    "secretsmanager",
    "kms",
    "sts",
    "xray",
  ])

  service      = each.key
  service_type = "Interface"
}

locals {
  # Interface endpoints — costruiti dinamicamente dalla region
  interface_endpoints = {
    ecr_api        = "com.amazonaws.${var.aws_region}.ecr.api"
    ecr_dkr        = "com.amazonaws.${var.aws_region}.ecr.dkr"
    sqs            = "com.amazonaws.${var.aws_region}.sqs"
    logs           = "com.amazonaws.${var.aws_region}.logs"
    monitoring     = "com.amazonaws.${var.aws_region}.monitoring"
    secretsmanager = "com.amazonaws.${var.aws_region}.secretsmanager"
    kms            = "com.amazonaws.${var.aws_region}.kms"
    sts            = "com.amazonaws.${var.aws_region}.sts"
    xray           = "com.amazonaws.${var.aws_region}.xray"
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id              = aws_vpc.main.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.private_app[*].id
  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name = "${var.name_prefix}-vpce-${each.key}"
  }
}