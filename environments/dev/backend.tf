# ═══════════════════════════════════════════════════════════
# TERRAFORM REMOTE STATE — Region Milano
# ═══════════════════════════════════════════════════════════

terraform {
  backend "s3" {
    bucket         = "acme-terraform-state-dev"
    key            = "dashboard/terraform.tfstate"
    region         = "eu-south-1" # Milano — state nella stessa region
    encrypt        = true
    dynamodb_table = "acme-terraform-locks"
  }
}