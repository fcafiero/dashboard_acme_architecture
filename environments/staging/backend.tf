terraform {
  backend "s3" {
    bucket         = "acme-terraform-state-staging"
    key            = "dashboard/terraform.tfstate"
    region         = "eu-central-1" # Francoforte
    encrypt        = true
    dynamodb_table = "acme-terraform-locks"
  }
}