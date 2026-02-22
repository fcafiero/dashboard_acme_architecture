# Terraform — ACME Dashboard Infrastructure

> **Infrastruttura AWS production-grade** per `dashboard.acme.com`, completamente gestita via Terraform.  
> Region principale: `eu-south-1` (Milano) · Multi-AZ · Serverless-first

---

## Indice

1. [Panoramica architetturale](#1-panoramica-architetturale)
2. [Struttura del repository](#2-struttura-del-repository)
3. [Moduli Terraform](#3-moduli-terraform)
4. [Variabili globali](#4-variabili-globali)
5. [Output principali](#5-output-principali)
6. [Prerequisiti](#6-prerequisiti)
7. [Bootstrap (prima esecuzione)](#7-bootstrap-prima-esecuzione)
8. [Deploy per ambiente](#8-deploy-per-ambiente)
9. [Auto-scaling e capacità](#9-auto-scaling-e-capacità)
10. [Sicurezza e compliance](#10-sicurezza-e-compliance)
11. [Osservabilità](#11-osservabilità)
12. [Convenzioni di tagging](#12-convenzioni-di-tagging)
13. [Note operative](#13-note-operative)

---

## 1. Panoramica architetturale

L'infrastruttura implementa una piattaforma **event-driven** e **multi-tier** con separazione netta tra workload interattivi (dashboard utenti) e workload batch (ETL, report).

```
Internet
   │
   ▼
Route 53 (Alias Record)
   │
   ▼
CloudFront CDN (450+ PoP) ──── WAF v2 (Managed Rules)
   │                             │ TLS terminato all'edge
   ▼                             │
ALB (subnet pubbliche, Multi-AZ)◄┘
   │
   ├─► ECS Fargate Web/API   ──► ElastiCache Redis (cache + sessioni)
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
KMS: cifratura at-rest per S3, Aurora, SQS, Secrets Manager
CloudTrail + VPC Flow Logs + X-Ray: audit e osservabilità completa
```

### Componenti per layer

| Layer | Servizi AWS |
|---|---|
| **Edge** | Route 53, CloudFront, WAF v2, ACM |
| **Networking** | VPC `/16`, subnet pubbliche/private/DB, NAT Gateway (per AZ), VPC Endpoints |
| **Compute** | ECS Fargate (3 servizi), ALB, ECR |
| **Database** | Aurora PostgreSQL (Writer + Reader auto-scaling), ElastiCache Redis |
| **Storage** | S3 Raw Data, S3 Reports (lifecycle policies, SSE-KMS) |
| **Messaging** | SQS ETL Queue + DLQ, SQS Report Queue + DLQ |
| **Security** | KMS CMK, IAM (least privilege), Secrets Manager, CloudTrail |
| **Observability** | CloudWatch Alarms + Dashboards, X-Ray, VPC Flow Logs, SNS |

---

## 2. Struttura del repository

```
dashboard_acme_architecture/
├── main.tf                  # Orchestrazione di tutti i moduli
├── variables.tf             # Variabili globali con validazione
├── outputs.tf               # Output principali (URL, ARN, endpoint)
├── providers.tf             # Provider AWS principale + alias us-east-1
├── versions.tf              # Vincoli Terraform e provider
│
├── modules/
│   ├── networking/          # VPC, subnet, NAT GW, VPC Endpoints, Security Groups
│   ├── security/            # KMS, IAM roles/policies, Secrets Manager, CloudTrail, WAF
│   ├── storage/             # S3 buckets (Raw + Reports), lifecycle rules, encryption
│   ├── messaging/           # SQS queues (ETL + Report) con DLQ
│   ├── database/            # Aurora PostgreSQL cluster, ElastiCache Redis
│   ├── compute/             # ECS cluster, 3 Fargate services, ALB, ECR, Auto-scaling
│   ├── edge/                # Route 53, CloudFront distribution, ACM certificates
│   └── observability/       # CloudWatch alarms/dashboards, X-Ray, VPC Flow Logs, SNS
│
└── environments/
    ├── dev/                 # terraform.tfvars per Development
    ├── staging/             # terraform.tfvars per Staging
    └── prod/                # terraform.tfvars per Production
```

---

## 3. Moduli Terraform

### 3.1 `networking`

Crea la VPC con architettura a tre livelli:

- **Subnet pubbliche**: ALB e NAT Gateway (una per AZ)
- **Subnet private applicazione**: ECS Fargate tasks (nessun accesso diretto da internet)
- **Subnet private database**: Aurora e ElastiCache (isolate, nessuna route outbound)
- **VPC Endpoints (PrivateLink)** per S3 (Gateway), SQS, ECR API/DKR, CloudWatch, Secrets Manager — il traffico verso questi servizi non esce mai su internet
- **Security Groups** granulari per ALB, ECS Web, ECS ETL, ECS Report, Aurora, Redis

| Variabile input | Descrizione |
|---|---|
| `vpc_cidr` | CIDR block VPC (default `10.0.0.0/16`) |
| `availability_zones` | AZ da usare (se vuoto, risolte dinamicamente) |
| `aws_region` | Region di deployment |

### 3.2 `security`

- **KMS Customer Managed Key (CMK)**: chiave master per S3, Aurora, SQS, Secrets Manager
- **IAM Roles** (least privilege) per ECS Execution e per ogni Task (Web, ETL, Report) — ogni ruolo accede solo alle risorse necessarie
- **Secrets Manager**: credenziali Aurora con rotazione automatica; secret recuperati a runtime dai container tramite VPC Endpoint
- **WAF v2** (scope `CLOUDFRONT`, deployato in `us-east-1`): AWS Managed Rules (Common, SQLi, Known Bad Inputs), rate limiting, IP reputation list
- **CloudTrail**: trail multi-region con log su S3, integrato con CloudWatch Logs per alerting real-time

> ⚠️ Il modulo `security` richiede il **provider alias `aws.us_east_1`** per il WAF CloudFront.

### 3.3 `storage`

| Bucket | Scopo | Lifecycle |
|---|---|---|
| `{prefix}-raw-data` | File caricati dagli utenti (CSV/Excel pre-ETL) | Transizione a S3-IA dopo 30 giorni, Glacier dopo 90, eliminazione dopo 365 |
| `{prefix}-reports` | PDF generati dai Report Workers | Transizione a S3-IA dopo 60 giorni |

Entrambi i bucket sono configurati con:
- **SSE-KMS** (chiave dal modulo `security`)
- **Versioning** abilitato
- **Public access block** completo
- **S3 Event Notification** verso SQS ETL Queue (solo bucket Raw, su evento `s3:ObjectCreated:*`)

### 3.4 `messaging`

| Coda | Consumer | DLQ | Visibility Timeout |
|---|---|---|---|
| `{prefix}-etl-jobs` | ECS ETL Workers | `{prefix}-etl-jobs-dlq` | 30 min (sufficiente per file 2 GB) |
| `{prefix}-report-jobs` | ECS Report Workers | `{prefix}-report-jobs-dlq` | 15 min |

- Tutte le code sono cifrate con KMS
- **maxReceiveCount = 3**: dopo 3 tentativi falliti, il messaggio va in DLQ
- **Retention**: 14 giorni sulle code principali, 14 giorni sulle DLQ

### 3.5 `database`

**Aurora PostgreSQL:**
- Cluster Multi-AZ con istanza Writer e Reader auto-scaling (1–5 repliche)
- Instance class configurabile via `var.aurora_instance_class` (default `db.r6g.large`)
- Storage auto-growing, encryption at-rest con KMS
- Backup automatici con retention 7 giorni, snapshot manuale pre-destroy
- Endpoint separati per Writer e Reader (CQRS infrastrutturale)

**ElastiCache Redis:**
- Modalità Cluster con replica Multi-AZ
- Node type configurabile (default `cache.r6g.large`)
- Automatic failover abilitato
- In-transit encryption + at-rest encryption

### 3.6 `compute`

- **ECS Cluster** con Container Insights abilitati
- **3 Fargate Services** con profili di risorse differenziati:

| Servizio | CPU | RAM | Capacity | Scaling trigger |
|---|---|---|---|---|
| Web/API | 1 vCPU | 2 GB | Standard | CPU 60% + ALB Request Count |
| ETL Workers | 4 vCPU | 8 GB | **Spot** | SQS Queue Depth |
| Report Workers | 2 vCPU | 4 GB | Standard | SQS Queue Depth |

- **ALB** in subnet pubbliche con listener HTTPS (ACM cert regionale), health check su `/health`
- **ECR Repositories** per le tre immagini applicative
- **Application Auto Scaling** con policy separate per ogni servizio
- Immagini configurabili via variabili (`web_api_image`, `etl_worker_image`, `report_worker_image`)

### 3.7 `edge`

> ⚠️ Richiede il **provider alias `aws.us_east_1`** per ACM e WAF CloudFront.

- **Route 53**: Alias Record `dashboard.acme.com` → CloudFront
- **ACM**: due certificati — uno in `us-east-1` (CloudFront) e uno nella region principale (ALB)
- **CloudFront**: distribuzione con WAF allegato, origini per ALB (API dinamiche) e S3 Reports (PDF con OAC), cache behavior differenziati per asset statici vs. API
- **Origin Access Control (OAC)** per accesso CloudFront → S3 Reports senza rendere il bucket pubblico

### 3.8 `observability`

- **CloudWatch Alarms** con notifiche SNS via email su:
  - DLQ non vuote (file ETL o report falliti)
  - CPU Web/API > 80% per 5 minuti
  - Latenza ALB P95 > soglia configurabile
  - Aurora CPU > 70%
  - Redis evictions > 0
- **CloudWatch Dashboard** unificata con widget per tutti i servizi
- **X-Ray** abilitato su ECS per distributed tracing
- **VPC Flow Logs** inviati a CloudWatch Logs con retention 30 giorni

---

## 4. Variabili globali

| Variabile | Tipo | Default | Descrizione |
|---|---|---|---|
| `project_name` | string | `acme-dashboard` | Prefisso per tutte le risorse |
| `environment` | string | — | `dev` / `staging` / `prod` |
| `aws_region` | string | `eu-south-1` | Region principale (validata) |
| `domain_name` | string | `dashboard.acme.com` | FQDN applicazione |
| `hosted_zone_name` | string | `acme.com` | Hosted Zone Route 53 esistente |
| `vpc_cidr` | string | `10.0.0.0/16` | CIDR block VPC |
| `availability_zones` | list | `[]` | Se vuoto, risolte dinamicamente dalla region |
| `aurora_instance_class` | string | `db.r6g.large` | Classe istanza Aurora |
| `aurora_min_reader_count` | number | `1` | Repliche Aurora minime |
| `aurora_max_reader_count` | number | `5` | Repliche Aurora massime |
| `redis_node_type` | string | `cache.r6g.large` | Tipo nodo ElastiCache |
| `web_api_image` | string | `""` | URI immagine ECR Web/API |
| `etl_worker_image` | string | `""` | URI immagine ECR ETL |
| `report_worker_image` | string | `""` | URI immagine ECR Report |
| `web_min_capacity` | number | `2` | Task Web/API minini (HA garantita) |
| `web_max_capacity` | number | `10` | Task Web/API massimi |
| `etl_min_capacity` | number | `0` | ETL min (scale-to-zero) |
| `etl_max_capacity` | number | `20` | ETL max |
| `report_min_capacity` | number | `0` | Report min (scale-to-zero) |
| `report_max_capacity` | number | `10` | Report max |
| `alert_email` | string | — | Email destinatario allarmi CloudWatch |

---

## 5. Output principali

| Output | Descrizione | Sensibile |
|---|---|---|
| `dashboard_url` | `https://dashboard.acme.com` | No |
| `deployment_region` | Region AWS utilizzata | No |
| `availability_zones` | AZ effettivamente usate | No |
| `cloudfront_distribution_id` | ID distribuzione CloudFront | No |
| `alb_dns_name` | DNS name ALB (interno) | No |
| `aurora_writer_endpoint` | Endpoint Aurora Writer | **Sì** |
| `aurora_reader_endpoint` | Endpoint Aurora Reader | **Sì** |
| `s3_raw_bucket` | Nome bucket S3 Raw Data | No |
| `ecr_repository_urls` | URL repository ECR per le 3 immagini | No |
| `ecs_cluster_name` | Nome cluster ECS | No |

---

## 6. Prerequisiti

1. **AWS CLI** configurato con credenziali con permessi sufficienti (AdministratorAccess o policy custom documentata)
2. **Terraform** >= `1.7.0`
3. **AWS Provider** `~> 5.60`
4. **Hosted Zone Route 53** per `acme.com` già esistente nell'account AWS target
5. **S3 bucket + DynamoDB table** per il remote state Terraform (vedi Bootstrap)
6. Immagini Docker delle 3 applicazioni già pubblicate su ECR (o registry accessibile)

---

## 7. Bootstrap (prima esecuzione)

Il backend Terraform richiede un bucket S3 e una tabella DynamoDB pre-esistenti per il locking distribuito dello state. Eseguire **una sola volta** per account/region:

```bash
# Creare il bucket S3 per lo state (versioning obbligatorio)
aws s3 mb s3://acme-terraform-state-prod --region eu-south-1
aws s3api put-bucket-versioning \
  --bucket acme-terraform-state-prod \
  --versioning-configuration Status=Enabled

# Creare la tabella DynamoDB per il lock
aws dynamodb create-table \
  --table-name acme-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region eu-south-1

# (opzionale) Abilitare encryption sul bucket state
aws s3api put-bucket-encryption \
  --bucket acme-terraform-state-prod \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms"}}]}'
```

Configurare il backend nel file `backend.tf` (non incluso nel repo, da creare per environment):

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

## 8. Deploy per ambiente

Ogni ambiente ha la propria directory con il file `terraform.tfvars`:

```bash
cd environments/prod

# Prima inizializzazione (scarica providers e configura backend)
terraform init

# Piano delle modifiche
terraform plan -var-file="terraform.tfvars" -out=tfplan

# Applicazione (richiede conferma esplicita)
terraform apply tfplan
```

### Esempio `terraform.tfvars` per Production

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

### Destroy (attenzione: distrugge tutto)

```bash
terraform destroy -var-file="terraform.tfvars"
```

> ⚠️ Il bucket S3 Raw Data e il bucket Reports hanno `prevent_destroy = true` e il bucket stato non viene rimosso automaticamente.

---

## 9. Auto-scaling e capacità

### ECS Web/API
- Scala su **CPU medio > 60%** e su **ALB Request Count per target**
- Minimo 2 task (uno per AZ) per garantire HA anche durante scaling events
- Scale-out: nuovi task pronti in ~60 secondi

### ECS ETL Workers (Fargate Spot)
- Scala sulla **profondità della coda SQS** (`ApproximateNumberOfMessagesVisible`)
- `min = 0`: nessun task attivo quando la coda è vuota (costo zero)
- `max = 20`: elaborazione parallela di fino a 20 file contemporaneamente
- Se un task Spot viene interrotto, il messaggio ritorna in coda e viene ripreso da un altro worker

### ECS Report Workers
- Stessa logica ETL ma su coda SQS Report
- Capacity Standard (non Spot) per rispettare le aspettative di completamento degli utenti

### Aurora Reader Auto-scaling
- Scala da `aurora_min_reader_count` a `aurora_max_reader_count` repliche
- Trigger: CPU media cluster > 70% o numero connessioni attive

---

## 10. Sicurezza e compliance

| Controllo | Implementazione |
|---|---|
| Encryption at-rest | KMS CMK per S3, Aurora, SQS, Secrets Manager |
| Encryption in-transit | TLS 1.2+ ovunque; Redis in-transit encryption |
| Network isolation | Container in subnet private; DB in subnet isolate |
| Secrets management | Secrets Manager con rotazione automatica (30-90 gg) |
| WAF | AWS Managed Rules + rate limiting su CloudFront |
| Audit trail | CloudTrail multi-region + VPC Flow Logs |
| IAM least privilege | Task role separato per ogni servizio ECS |
| Vulnerability scanning | ECR Image Scanning abilitato su push |
| Public access | S3 public access block; no risorse DB/App con IP pubblico |

---

## 11. Osservabilità

### Allarmi critici (notifica SNS → email)

| Allarme | Soglia | Azione suggerita |
|---|---|---|
| DLQ ETL non vuota | `ApproximateNumberOfMessagesVisible > 0` | Analizzare i messaggi falliti, verificare log ETL |
| DLQ Report non vuota | `ApproximateNumberOfMessagesVisible > 0` | Analizzare errori Report Worker |
| Web/API CPU alta | `> 80%` per 5 min | Aumentare `web_max_capacity` o ottimizzare applicazione |
| ALB 5xx rate | `> 1%` per 5 min | Verificare health delle Fargate Tasks |
| Aurora CPU | `> 70%` per 10 min | Verificare query lente, aggiungere repliche Reader |
| SQS Message Age | `ApproximateAgeOfOldestMessage > 1800s` | ETL in ritardo, verificare worker e coda |

### Dashboard CloudWatch
La dashboard unificata mostra in tempo reale: task ECS attivi e CPU per servizio, latenza ALB (P50/P95/P99), profondità code SQS, connessioni Aurora e Redis, hit rate cache Redis.

### X-Ray Tracing
I servizi ECS hanno X-Ray daemon abilitato. Il tracing end-to-end permette di identificare latenze per segmento: CloudFront → ALB → ECS → Redis/Aurora.

---

## 12. Convenzioni di tagging

Tutti i provider applicano automaticamente i seguenti tag via `default_tags`:

| Tag | Valore |
|---|---|
| `Project` | `var.project_name` |
| `Environment` | `var.environment` |
| `ManagedBy` | `terraform` |
| `Owner` | `platform-team` |
| `Region` | `var.aws_region` |

---

## 13. Note operative

### Aggiornamento immagini Docker (rolling deploy)

Per aggiornare un'immagine senza cambiare infrastruttura, aggiornare la variabile `*_image` con il nuovo tag e rieseguire `terraform apply`. ECS esegue automaticamente un rolling deployment con zero downtime (nuovi task avviati prima di drainare i vecchi).

### Cambio region

La variabile `aws_region` permette di cambiare la region principale. Le AZ vengono risolte dinamicamente. WAF e ACM CloudFront restano sempre in `us-east-1` (requisito AWS per risorse globali).

### Scaling manuale emergenziale

```bash
# Aumentare temporaneamente i task Web/API
aws ecs update-service \
  --cluster acme-dashboard-prod \
  --service acme-dashboard-prod-web \
  --desired-count 8 \
  --region eu-south-1
```

### Connessione al database (via SSM Session Manager)

Non ci sono bastion host. Connettersi ad Aurora tramite ECS Exec abilitato sui container Web/API, oppure tramite AWS Systems Manager Session Manager su un'istanza EC2 temporanea in subnet privata.

### Costi stimati (prod, carico medio)

| Servizio | Stima mensile |
|---|---|
| ECS Fargate (Web 2-4 task) | ~$80-160 |
| ECS Fargate Spot (ETL, utilizzo variabile) | ~$20-60 |
| Aurora PostgreSQL (1 Writer + 1 Reader `r6g.large`) | ~$280 |
| ElastiCache Redis (`r6g.large`, Multi-AZ) | ~$180 |
| CloudFront + WAF | ~$30-80 |
| S3 + Data Transfer | ~$20-50 |
| ALB, NAT GW, VPC Endpoints | ~$50 |
| **Totale stimato** | **~$660–860/mese** |

> I costi ETL sono variabili e dipendono dal volume di file elaborati. Con scale-to-zero, il costo dei worker è proporzionale all'utilizzo effettivo.
