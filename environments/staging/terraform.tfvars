# ═══════════════════════════════════════════════════════════
# STAGING ENVIRONMENT
# ═══════════════════════════════════════════════════════════
# Esempio di deploy in region diversa (Francoforte) per
# dimostrare la configurabilità della region.
# ═══════════════════════════════════════════════════════════

environment      = "staging"
project_name     = "acme-dashboard"
domain_name      = "dashboard.staging.acme.com"
hosted_zone_name = "acme.com"

# ── Region diversa per dimostrare la portabilità ────────
aws_region = "eu-central-1" # Francoforte

# AZ — risolte automaticamente per eu-central-1
availability_zones = []

vpc_cidr = "10.2.0.0/16"

aurora_instance_class   = "db.r6g.medium"
aurora_min_reader_count = 1
aurora_max_reader_count = 3
redis_node_type         = "cache.r6g.medium"

web_min_capacity    = 2
web_max_capacity    = 6
etl_min_capacity    = 0
etl_max_capacity    = 10
report_min_capacity = 0
report_max_capacity = 5

alert_email = "staging-alerts@acme.com"