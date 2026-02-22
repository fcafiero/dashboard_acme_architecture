# ═══════════════════════════════════════════════════════════
# AWS PROVIDERS
# ═══════════════════════════════════════════════════════════
# Provider principale: region configurabile (default eu-south-1 Milano)
# Provider us-east-1: OBBLIGATORIO per risorse globali
#   - CloudFront richiede certificati ACM in us-east-1
#   - WAF scope CLOUDFRONT deve essere in us-east-1
# ═══════════════════════════════════════════════════════════

provider "aws" {
  region = var.aws_region # Default: eu-south-1 (Milano)

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "platform-team"
      Region      = var.aws_region
    }
  }
}

# Provider dedicato per risorse globali — SEMPRE us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "platform-team"
      Region      = "us-east-1 (global resources)"
    }
  }
}