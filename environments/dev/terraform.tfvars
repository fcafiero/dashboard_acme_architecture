# ═══════════════════════════════════════════════════════════
# DEVELOPMENT ENVIRONMENT — Region Milano (stessa del prod
# per consistenza, sovrascrivibile)
# ═══════════════════════════════════════════════════════════

environment      = "dev"
project_name     = "acme-dashboard"
domain_name      = "dashboard.dev.acme.com"
hosted_zone_name = "acme.com"

# Region — Milano, stessa del prod per consistenza
aws_region = "eu-south-1"

# AZ — risoluzione dinamica
availability_zones = []

# VPC — CIDR diverso dal prod per evitare conflitti in caso di peering
vpc_cidr = "10.1.0.0/16"

# Database — istanze più piccole per risparmiare
aurora_instance_class   = "db.r6g.medium"
aurora_min_reader_count = 1
aurora_max_reader_count = 2
redis_node_type         = "cache.r6g.medium"

# Scaling — ridotto
web_min_capacity    = 1
web_max_capacity    = 4
etl_min_capacity    = 0
etl_max_capacity    = 5
report_min_capacity = 0
report_max_capacity = 3

alert_email = "dev-alerts@acme.com"