# 🚀 Terraform — ACME Dashboard Infrastructure

[![AWS](https://img.shields.io/badge/Cloud-AWS-FF9900?logo=amazon-aws&logoColor=white)](https://aws.amazon.com/)
[![Terraform](https://img.shields.io/badge/Infrastructure-Terraform-7B42BC?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![ECS Fargate](https://img.shields.io/badge/Compute-ECS%20Fargate-FF9900?logo=amazon-ecs&logoColor=white)](https://aws.amazon.com/fargate/)
[![Aurora PostgreSQL](https://img.shields.io/badge/Database-Aurora%20PostgreSQL-336791?logo=postgresql&logoColor=white)](https://aws.amazon.com/rds/aurora/)
[![Redis](https://img.shields.io/badge/Cache-ElastiCache%20Redis-DC382D?logo=redis&logoColor=white)](https://aws.amazon.com/elasticache/)
[![CloudFront](https://img.shields.io/badge/CDN-CloudFront-8C4FFF?logo=amazonaws&logoColor=white)](https://aws.amazon.com/cloudfront/)

> **Production-grade AWS infrastructure** for `dashboard.acme.com`, fully managed via Terraform.
> Primary region: `eu-south-1` (Milan) · Multi-AZ · Serverless-first

---

## 📑 Table of Contents

1. [Architecture overview](#1-architecture-overview)
2. [Repository structure](#2-repository-structure)
3. [Terraform modules](#3-terraform-modules)
4. [Global variables](#4-global-variables)
5. [Main outputs](#5-main-outputs)
6. [Prerequisites](#6-prerequisites)
7. [Bootstrap (first run)](#7-bootstrap-first-run)
8. [Deploy per environment](#8-deploy-per-environment)
9. [Auto-scaling and capacity](#9-auto-scaling-and-capacity)
10. [Security and compliance](#10-security-and-compliance)
11. [Observability](#11-observability)
12. [Tagging conventions](#12-tagging-conventions)
13. [Operational notes](#13-operational-notes)

---

## 1. 🏛️ Architecture overview

The infrastructure implements an **event-driven**, **multi-tier** platform with a clean separation between interactive workloads (user dashboard) and batch workloads (ETL, reporting).

```
Internet
   │
   ▼
Route 53 (Alias Record)
   │
   ▼
CloudFront CDN (450+ PoPs) ──── WAF v2 (Managed Rules)
   │                             │ TLS terminated at the edge
   ▼                             │
ALB (public subnets, Multi-AZ)◄┘
   │
   ├─► ECS Fargate Web/API   ──► ElastiCache Redis (cache + sessions)
   │        │                          │
   │        └──────────────────────────┼──► Aurora PostgreSQL Reader
   │                                   │        (auto-scaling 1-5 replicas)
   │
   ├─► ECS Fargate ETL Workers ──► S3 Raw Bucket ──► Aurora Writer
   │        ▲                                              │
   │       SQS ETL Queue ◄── S3 Event Notification        │
   │                                                       ▼
   └─► ECS Fargate Report Workers ──► Aurora Reader ──► S3 Reports
            ▲                              └──────────────► SES (email)
           SQS Report Queue

VPC Endpoints (PrivateLink): S3, SQS, ECR, CloudWatch, Secrets Manager
KMS: encryption at rest for S3, Aurora, SQS, Secrets Manager
CloudTrail + VPC Flow Logs + X-Ray: full audit and observability
```

### Components by layer

| Layer | AWS Services |
|---|---|
| **Edge** | Route 53, CloudFront, WAF v2, ACM |
| **Networking** | VPC `/16`, public/private/DB subnets, NAT Gateway (per AZ), VPC Endpoints |
| **Compute** | ECS Fargate (3 services), ALB, ECR |
| **Database** | Aurora PostgreSQL (Writer + auto-scaling Reader), ElastiCache Redis |
| **Storage** | S3 Raw Data, S3 Reports (lifecycle policies, SSE-KMS) |
| **Messaging** | SQS ETL Queue + DLQ, SQS Report Queue + DLQ |
| **Security** | KMS CMK, IAM (least privilege), Secrets Manager, CloudTrail |
| **Observability** | CloudWatch Alarms + Dashboards, X-Ray, VPC Flow Logs, SNS |

---

## 2. 📂 Repository structure

```
dashboard_acme_architecture/
├── main.tf                  # Orchestration of all modules
├── variables.tf             # Global variables with validation
├── outputs.tf                # Main outputs (URL, ARN, endpoint)
├── providers.tf             # Main AWS provider + us-east-1 alias
├── versions.tf              # Terraform and provider constraints
│
├── modules/
│   ├── networking/          # VPC, subnets, NAT GW, VPC Endpoints, Security Groups
│   ├── security/            # KMS, IAM roles/policies, Secrets Manager, CloudTrail, WAF
│   ├── storage/             # S3 buckets (Raw + Reports), lifecycle rules, encryption
│   ├── messaging/           # SQS queues (ETL + Report) with DLQ
│   ├── database/            # Aurora PostgreSQL cluster, ElastiCache Redis
│   ├── compute/             # ECS cluster, 3 Fargate services, ALB, ECR, Auto-scaling
│   ├── edge/                # Route 53, CloudFront distribution, ACM certificates
│   └── observability/       # CloudWatch alarms/dashboards, X-Ray, VPC Flow Logs, SNS
│
└── environments/
    ├── dev/                 # terraform.tfvars for Development
    ├── staging/             # terraform.tfvars for Staging
    └── prod/                # terraform.tfvars for Production
```

---

## 3. 🛠️ Terraform modules

### 3.1 `networking`

Creates the VPC with a three-tier architecture:

- **Public subnets**: ALB and NAT Gateway (one per AZ)
- **Private application subnets**: ECS Fargate tasks (no direct internet access)
- **Private database subnets**: Aurora and ElastiCache (isolated, no outbound route)
- **VPC Endpoints (PrivateLink)** for S3 (Gateway), SQS, ECR API/DKR, CloudWatch, Secrets Manager — traffic to these services never leaves the network over the internet
- Granular **Security Groups** for ALB, ECS Web, ECS ETL, ECS Report, Aurora, Redis

| Input variable | Description |
|---|---|
| `vpc_cidr` | VPC CIDR block (default `10.0.0.0/16`) |
| `availability_zones` | AZs to use (if empty, resolved dynamically) |
| `aws_region` | Deployment region |

### 3.2 `security`

- **KMS Customer Managed Key (CMK)**: master key for S3, Aurora, SQS, Secrets Manager
- **IAM Roles** (least privilege) for ECS Execution and for each Task (Web, ETL, Report) — each role only accesses the resources it needs
- **Secrets Manager**: Aurora credentials with automatic rotation; secrets retrieved at runtime by containers via VPC Endpoint
- **WAF v2** (scope `CLOUDFRONT`, deployed in `us-east-1`): AWS Managed Rules (Common, SQLi, Known Bad Inputs), rate limiting, IP reputation list
- **CloudTrail**: multi-region trail with logs on S3, integrated with CloudWatch Logs for real-time alerting

> ⚠️ The `security` module requires the **`aws.us_east_1` provider alias** for the CloudFront WAF.

### 3.3 `storage`

| Bucket | Purpose | Lifecycle |
|---|---|---|
| `{prefix}-raw-data` | Files uploaded by users (pre-ETL CSV/Excel) | Transition to S3-IA after 30 days, Glacier after 90, deletion after 365 |
| `{prefix}-reports` | PDFs generated by the Report Workers | Transition to S3-IA after 60 days |

Both buckets are configured with:
- **SSE-KMS** (key from the `security` module)
- **Versioning** enabled
- Full **public access block**
- **S3 Event Notification** to the SQS ETL Queue (Raw bucket only, on `s3:ObjectCreated:*` events)

### 3.4 `messaging`

| Queue | Consumer | DLQ | Visibility Timeout |
|---|---|---|---|
| `{prefix}-etl-jobs` | ECS ETL Workers | `{prefix}-etl-jobs-dlq` | 30 min (sufficient for 2 GB files) |
| `{prefix}-report-jobs` | ECS Report Workers | `{prefix}-report-jobs-dlq` | 15 min |

- All queues are KMS-encrypted
- **maxReceiveCount = 3**: after 3 failed attempts, the message goes to the DLQ
- **Retention**: 14 days on the main queues, 14 days on the DLQs

### 3.5 `database`

**Aurora PostgreSQL:**
- Multi-AZ cluster with a Writer instance and auto-scaling Reader (1–5 replicas)
- Instance class configurable via `var.aurora_instance_class` (default `db.r6g.large`)
- Auto-growing storage, encryption at rest with KMS
- Automatic backups with 7-day retention, manual snapshot pre-destroy
- Separate endpoints for Writer and Reader (infrastructural CQRS)

**ElastiCache Redis:**
- Cluster mode with Multi-AZ replication
- Configurable node type (default `cache.r6g.large`)
- Automatic failover enabled
- In-transit encryption + at-rest encryption

### 3.6 `compute`

- **ECS Cluster** with Container Insights enabled
- **3 Fargate Services** with differentiated resource profiles:

| Service | CPU | RAM | Capacity | Scaling trigger |
|---|---|---|---|---|
| Web/API | 1 vCPU | 2 GB | Standard | CPU 60% + ALB Request Count |
| ETL Workers | 4 vCPU | 8 GB | **Spot** | SQS Queue Depth |
| Report Workers | 2 vCPU | 4 GB | Standard | SQS Queue Depth |

- **ALB** in public subnets with an HTTPS listener (regional ACM cert), health check on `/health`
- **ECR Repositories** for the three application images
- **Application Auto Scaling** with separate policies for each service
- Images configurable via variables (`web_api_image`, `etl_worker_image`, `report_worker_image`)

### 3.7 `edge`

> ⚠️ Requires the **`aws.us_east_1` provider alias** for ACM and CloudFront WAF.

- **Route 53**: Alias Record `dashboard.acme.com` → CloudFront
- **ACM**: two certificates — one in `us-east-1` (CloudFront) and one in the primary region (ALB)
- **CloudFront**: distribution with WAF attached, origins for ALB (dynamic APIs) and S3 Reports (PDFs with OAC), differentiated cache behaviors for static assets vs. API
- **Origin Access Control (OAC)** for CloudFront → S3 Reports access without making the bucket public

### 3.8 `observability`

- **CloudWatch Alarms** with SNS email notifications on:
  - Non-empty DLQs (failed ETL or report files)
  - Web/API CPU > 80% for 5 minutes
  - ALB P95 latency above a configurable threshold
  - Aurora CPU > 70%
  - Redis evictions > 0
- Unified **CloudWatch Dashboard** with widgets for all services
- **X-Ray** enabled on ECS for distributed tracing
- **VPC Flow Logs** sent to CloudWatch Logs with 30-day retention

---

## 4. ⚙️ Global variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `project_name` | string | `acme-dashboard` | Prefix for all resources |
| `environment` | string | — | `dev` / `staging` / `prod` |
| `aws_region` | string | `eu-south-1` | Primary region (validated) |
| `domain_name` | string | `dashboard.acme.com` | Application FQDN |
| `hosted_zone_name` | string | `acme.com` | Existing Route 53 Hosted Zone |
| `vpc_cidr` | string | `10.0.0.0/16` | VPC CIDR block |
| `availability_zones` | list | `[]` | If empty, resolved dynamically from the region |
| `aurora_instance_class` | string | `db.r6g.large` | Aurora instance class |
| `aurora_min_reader_count` | number | `1` | Minimum Aurora replicas |
| `aurora_max_reader_count` | number | `5` | Maximum Aurora replicas |
| `redis_node_type` | string | `cache.r6g.large` | ElastiCache node type |
| `web_api_image` | string | `""` | Web/API ECR image URI |
| `etl_worker_image` | string | `""` | ETL ECR image URI |
| `report_worker_image` | string | `""` | Report ECR image URI |
| `web_min_capacity` | number | `2` | Minimum Web/API tasks (guaranteed HA) |
| `web_max_capacity` | number | `10` | Maximum Web/API tasks |
| `etl_min_capacity` | number | `0` | ETL minimum (scale-to-zero) |
| `etl_max_capacity` | number | `20` | ETL maximum |
| `report_min_capacity` | number | `0` | Report minimum (scale-to-zero) |
| `report_max_capacity` | number | `10` | Report maximum |
| `alert_email` | string | — | Recipient email for CloudWatch alarms |

---

## 5. 📤 Main outputs

| Output | Description | Sensitive |
|---|---|---|
| `dashboard_url` | `https://dashboard.acme.com` | No |
| `deployment_region` | AWS region used | No |
| `availability_zones` | AZs actually used | No |
| `cloudfront_distribution_id` | CloudFront distribution ID | No |
| `alb_dns_name` | ALB DNS name (internal) | No |
| `aurora_writer_endpoint` | Aurora Writer endpoint | **Yes** |
| `aurora_reader_endpoint` | Aurora Reader endpoint | **Yes** |
| `s3_raw_bucket` | S3 Raw Data bucket name | No |
| `ecr_repository_urls` | ECR repository URLs for the 3 images | No |
| `ecs_cluster_name` | ECS cluster name | No |

---

## 6. ✅ Prerequisites

1. **AWS CLI** configured with credentials that have sufficient permissions (AdministratorAccess or documented custom policy)
2. **Terraform** >= `1.7.0`
3. **AWS Provider** `~> 5.60`
4. **Route 53 Hosted Zone** for `acme.com` already existing in the target AWS account
5. **S3 bucket + DynamoDB table** for Terraform remote state (see Bootstrap)
6. Docker images for the 3 applications already published to ECR (or an accessible registry)

---

## 7. 🔧 Bootstrap (first run)

The Terraform backend requires a pre-existing S3 bucket and DynamoDB table for distributed state locking. Run **once only** per account/region:

```bash
# Create the S3 bucket for state (versioning required)
aws s3 mb s3://acme-terraform-state-prod --region eu-south-1
aws s3api put-bucket-versioning \
  --bucket acme-terraform-state-prod \
  --versioning-configuration Status=Enabled

# Create the DynamoDB table for locking
aws dynamodb create-table \
  --table-name acme-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region eu-south-1

# (optional) Enable encryption on the state bucket
aws s3api put-bucket-encryption \
  --bucket acme-terraform-state-prod \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms"}}]}'
```

Configure the backend in the `backend.tf` file (not included in the repo, to be created per environment):

```hcl
terraform {
  backend "s3" {
    bucket         = "acme-terraform-state-prod"
    key            = "dashboard/prod/terraform.tfstate"
    region         = "eu-south-1"
    dynamodb_table = "acme-terraform-locks"
    encrypt        = true
  }
}
```

---

## 8. 🚢 Deploy per environment

Each environment has its own directory with a `terraform.tfvars` file:

```bash
cd environments/prod

# First initialization (downloads providers and configures the backend)
terraform init

# Plan the changes
terraform plan -var-file="terraform.tfvars" -out=tfplan

# Apply (requires explicit confirmation)
terraform apply tfplan
```

### Example `terraform.tfvars` for Production

```hcl
project_name   = "acme-dashboard"
environment    = "prod"
aws_region     = "eu-south-1"
domain_name    = "dashboard.acme.com"
hosted_zone_name = "acme.com"

vpc_cidr = "10.0.0.0/16"

aurora_instance_class    = "db.r6g.large"
aurora_min_reader_count  = 1
aurora_max_reader_count  = 5
redis_node_type          = "cache.r6g.large"

web_api_image       = "123456789012.dkr.ecr.eu-south-1.amazonaws.com/acme-dashboard-web:latest"
etl_worker_image    = "123456789012.dkr.ecr.eu-south-1.amazonaws.com/acme-dashboard-etl:latest"
report_worker_image = "123456789012.dkr.ecr.eu-south-1.amazonaws.com/acme-dashboard-report:latest"

web_min_capacity    = 2
web_max_capacity    = 10
etl_min_capacity    = 0
etl_max_capacity    = 20
report_min_capacity = 0
report_max_capacity = 10

alert_email = "platform-team@acme.com"
```

### Destroy (caution: destroys everything)

```bash
terraform destroy -var-file="terraform.tfvars"
```

> ⚠️ The S3 Raw Data bucket and the Reports bucket have `prevent_destroy = true`, and the state bucket is not removed automatically.

---

## 9. 📈 Auto-scaling and capacity

### ECS Web/API
- Scales on **average CPU > 60%** and on **ALB Request Count per target**
- Minimum 2 tasks (one per AZ) to guarantee HA even during scaling events
- Scale-out: new tasks ready in ~60 seconds

### ECS ETL Workers (Fargate Spot)
- Scales on **SQS queue depth** (`ApproximateNumberOfMessagesVisible`)
- `min = 0`: no active tasks when the queue is empty (zero cost)
- `max = 20`: parallel processing of up to 20 files simultaneously
- If a Spot task is interrupted, the message returns to the queue and is picked up by another worker

### ECS Report Workers
- Same logic as ETL but on the SQS Report queue
- Standard capacity (not Spot) to meet user completion expectations

### Aurora Reader Auto-scaling
- Scales from `aurora_min_reader_count` to `aurora_max_reader_count` replicas
- Trigger: average cluster CPU > 70% or number of active connections

---

## 10. 🔐 Security and compliance

| Control | Implementation |
|---|---|
| Encryption at rest | KMS CMK for S3, Aurora, SQS, Secrets Manager |
| Encryption in transit | TLS 1.2+ everywhere; Redis in-transit encryption |
| Network isolation | Containers in private subnets; DBs in isolated subnets |
| Secrets management | Secrets Manager with automatic rotation (30-90 days) |
| WAF | AWS Managed Rules + rate limiting on CloudFront |
| Audit trail | Multi-region CloudTrail + VPC Flow Logs |
| IAM least privilege | Separate task role for each ECS service |
| Vulnerability scanning | ECR Image Scanning enabled on push |
| Public access | S3 public access block; no DB/App resources with public IP |

---

## 11. 📊 Observability

### Critical alarms (SNS notification → email)

| Alarm | Threshold | Suggested action |
|---|---|---|
| ETL DLQ not empty | `ApproximateNumberOfMessagesVisible > 0` | Analyze failed messages, check ETL logs |
| Report DLQ not empty | `ApproximateNumberOfMessagesVisible > 0` | Analyze Report Worker errors |
| High Web/API CPU | `> 80%` for 5 min | Increase `web_max_capacity` or optimize the application |
| ALB 5xx rate | `> 1%` for 5 min | Check the health of the Fargate Tasks |
| Aurora CPU | `> 70%` for 10 min | Check for slow queries, add Reader replicas |
| SQS Message Age | `ApproximateAgeOfOldestMessage > 1800s` | ETL running behind, check workers and queue |

### CloudWatch Dashboard
The unified dashboard shows in real time: active ECS tasks and CPU per service, ALB latency (P50/P95/P99), SQS queue depth, Aurora and Redis connections, Redis cache hit rate.

### X-Ray Tracing
ECS services have the X-Ray daemon enabled. End-to-end tracing makes it possible to identify latency per segment: CloudFront → ALB → ECS → Redis/Aurora.

---

## 12. 🏷️ Tagging conventions

All providers automatically apply the following tags via `default_tags`:

| Tag | Value |
|---|---|
| `Project` | `var.project_name` |
| `Environment` | `var.environment` |
| `ManagedBy` | `terraform` |
| `Owner` | `platform-team` |
| `Region` | `var.aws_region` |

---

## 13. 📝 Operational notes

### Updating Docker images (rolling deploy)

To update an image without changing infrastructure, update the `*_image` variable with the new tag and re-run `terraform apply`. ECS automatically performs a rolling deployment with zero downtime (new tasks are started before draining the old ones).

### Changing region

The `aws_region` variable allows the primary region to be changed. AZs are resolved dynamically. WAF and ACM for CloudFront always remain in `us-east-1` (AWS requirement for global resources).

### Manual emergency scaling

```bash
# Temporarily increase Web/API tasks
aws ecs update-service \
  --cluster acme-dashboard-prod \
  --service acme-dashboard-prod-web \
  --desired-count 8 \
  --region eu-south-1
```

### Connecting to the database (via SSM Session Manager)

There are no bastion hosts. Connect to Aurora via ECS Exec enabled on the Web/API containers, or via AWS Systems Manager Session Manager on a temporary EC2 instance in a private subnet.

### Estimated costs (prod, average load)

| Service | Monthly estimate |
|---|---|
| ECS Fargate (Web 2-4 tasks) | ~$80-160 |
| ECS Fargate Spot (ETL, variable usage) | ~$20-60 |
| Aurora PostgreSQL (1 Writer + 1 Reader `r6g.large`) | ~$280 |
| ElastiCache Redis (`r6g.large`, Multi-AZ) | ~$180 |
| CloudFront + WAF | ~$30-80 |
| S3 + Data Transfer | ~$20-50 |
| ALB, NAT GW, VPC Endpoints | ~$50 |
| **Estimated total** | **~$660–860/month** |

> ETL costs are variable and depend on the volume of files processed. With scale-to-zero, worker cost is proportional to actual usage.
