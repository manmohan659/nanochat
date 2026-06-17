# AWS/EKS Architecture Retained

This repository intentionally keeps the original SamosaChaat AWS/EKS platform
work as portfolio and DevOps-demo evidence. The AWS resources from that demo
were deleted after the demo to stop spend. Do not recreate them for the Railway
deployment, do not run `terraform apply`, and do not remove the AWS files.

## Retained Assets

- `terraform/`: AWS VPC, EKS, RDS, ECR, Route53, ACM, IAM, EFS, and environment
  stack definitions.
- `helm/`: SamosaChaat application chart plus the Prometheus, Grafana, Loki,
  Promtail, and Alertmanager observability chart.
- `.github/workflows/`: CI, build, deploy, Terraform, UAT promotion, release,
  nightly, and node patch workflows used by the DevOps demo.
- `scripts/`: runtime secret sync, RDS logical database bootstrap, smoke tests,
  AWS cost controls, node rotation, and schema-change demo scripts.
- `docs/`: architecture, runbook, defense, cost-control, and assignment docs.

The best existing overview is `docs/eks-architecture-defense.md`.

## Original Runtime Shape

The EKS deployment ran:

- `frontend`: Next.js web app.
- `auth`: FastAPI OAuth, session, JWT, and user service.
- `chat-api`: FastAPI conversation, message, admin, and inference orchestration
  API.
- `inference`: FastAPI model loading and generation service.
- AWS RDS PostgreSQL for users, conversations, and messages.

AWS infrastructure supplied the parts Railway now replaces:

- EKS managed nodes instead of Railway application services.
- RDS PostgreSQL instead of Railway Postgres.
- ECR image registry instead of Railway source/Dockerfile builds.
- ALB Ingress, Route53, and ACM instead of Railway public domains/TLS.
- Helm release orchestration instead of Railway service deploy settings.
- Prometheus, Grafana, Loki, Promtail, and Alertmanager instead of Railway logs
  and metrics for the low-budget deployment.

## Demo Capabilities Preserved In Code

- Blue/green production deployment through Helm values and ALB target switching.
- Helm pre-upgrade database migration jobs.
- Dev, QA, UAT, and prod environment separation.
- Shared non-prod RDS strategy plus physically isolated prod RDS strategy.
- HPA, PDB, ServiceMonitor, observability dashboards, and alerting manifests.
- GitHub Actions automation for build, deploy, promotion, release, Terraform,
  nightly checks, and node patching.

## Current Deployment Direction

Railway is now the active low-cost hosting target. Railway-specific docs and
templates should be added alongside the AWS assets. The AWS/EKS assets should
remain intact for evidence and future reference.

Use `docs/railway-deployment.md` for the Railway deployment path.
