# ═══════════════════════════════════════════════════════════
# EDGE MODULE — Provider Configuration
# ═══════════════════════════════════════════════════════════
# Questo modulo usa DUE provider AWS:
#   - aws          → region principale (per Route 53 records)
#   - aws.us_east_1 → us-east-1 (per ACM CloudFront + WAF)
#
# CloudFront è un servizio globale ma richiede:
#   - Certificati ACM in us-east-1
#   - WAF WebACL scope CLOUDFRONT in us-east-1
#
# I provider vengono passati dal modulo root tramite il
# blocco providers = { } nella chiamata del modulo.
# ═══════════════════════════════════════════════════════════

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.60"
      configuration_aliases = [aws.us_east_1]
    }
  }
}

# ── Locals ──────────────────────────────────────────────

locals {
  # Tag comuni per le risorse edge
  edge_tags = {
    Layer = "edge"
  }
}