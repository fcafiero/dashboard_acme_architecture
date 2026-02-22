# ═══════════════════════════════════════════════════════════
# PRODUCTION ENVIRONMENT — Region Milano
# ═══════════════════════════════════════════════════════════

environment    = "prod"
project_name   = "acme-dashboard"
domain_name    = "dashboard.acme.com"
hosted_zone_name = "acme.com"

# ══════════════════════════════════════════════════════════
# REGION — Milano come default, sovrascrivibile
# ══════════════════════════════════════════════════════════
aws_region = "eu-south-1" # Milano

# AZ — lasciate vuote per risoluzione dinamica dalla region
# Terraform selezionerà automaticamente eu-south-1a e eu-south-1b
# Per sovrascrivere:
# availability_zones = ["eu-south-1a", "eu-south-1b"]
availability_zones = []

vpc_cidr = "10.0.0.0/16"

# Database
aurora_instance_class   = "db.r6g.large"
aurora_min_reader_count = 1
aurora_max_reader_count = 5
redis_node_type         = "cache.r6g.large"

# Scaling
web_min_capacity    = 2
web_max_capacity    = 10
etl_min_capacity    = 0
etl_max_capacity    = 20
report_min_capacity = 0
report_max_capacity = 10

# Alerting
alert_email = "platform-alerts@acme.com"