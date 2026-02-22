# Terraform — ACME Dashboard Infrastructure

## Architettura

Questa configurazione Terraform implementa l'intera infrastruttura AWS per
`dashboard.acme.com`, inclusi:

- **Networking**: VPC Multi-AZ con subnet pubbliche/private, NAT Gateway, VPC Endpoints
- **Edge**: Route 53, CloudFront CDN, AWS WAF, certificati ACM
- **Compute**: ECS Fargate con 3 servizi (Web/API, ETL Workers, Report Workers)
- **Database**: Aurora PostgreSQL (Writer + Auto-scaling Readers), ElastiCache Redis
- **Storage**: S3 buckets (Raw Data, Reports) con lifecycle policies
- **Messaging**: SQS queues con Dead Letter Queues
- **Security**: KMS, IAM (least privilege), Secrets Manager, CloudTrail
- **Observability**: CloudWatch (alarms, dashboards), X-Ray, VPC Flow Logs

## Prerequisiti

1. AWS CLI configurato con credenziali appropriate
2. Terraform >= 1.7.0
3. Hosted Zone Route 53 per `acme.com` già esistente
4. S3 bucket + DynamoDB table per remote state (vedi bootstrap)

## Bootstrap (prima volta)

```bash
# Creare il bucket S3 per lo state e la DynamoDB table per il locking
aws s3 mb s3://acme-terraform-state-prod --region eu-south-1
aws dynamodb create-table \
  --table-name acme-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region eu-south-1