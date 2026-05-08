# samosaChaat Assignment Completion Plan

This is the grading path for the final EKS + RDS + Terraform + Git-driven
platform. The goal is not just to satisfy the literal checklist; it is to make
every claim reproducible, diagnosable, and defensible without AWS Console
deploy clicks.

## Final Architecture

- Frontend: Next.js service on EKS behind AWS ALB Ingress with HTTPS.
- Backend microservices:
  - `auth`: OAuth/JWT/user service.
  - `chat-api`: conversation API, RDS persistence, SSE orchestration.
  - `inference`: EKS-hosted model service.
- Database: AWS RDS PostgreSQL only. No in-cluster PostgreSQL.
- Infrastructure: Terraform owns VPC, EKS, managed nodes, RDS, ECR, IAM, EFS,
  ACM, Route53, remote state, and access entries.
- Observability: self-hosted Prometheus, Grafana, Alertmanager, Loki, and
  Promtail on EKS. Grafana is OAuth-only.

## Environments

| Runtime | Cluster | Namespace | Database | DNS |
| --- | --- | --- | --- | --- |
| dev | `samosachaat-dev-eks` | `samosachaat-dev` | `samosachaat_dev` | `dev.samosachaat.art` |
| QA nightly | `samosachaat-dev-eks` | `samosachaat-qa` | `samosachaat_qa` | `qa.samosachaat.art` |
| UAT | `samosachaat-dev-eks` | `samosachaat-uat` | `samosachaat_uat` | `uat.samosachaat.art` |
| prod | `samosachaat-prod-eks` | `samosachaat-prod` | `samosachaat_prod` | `samosachaat.art` |

Dev, QA, and UAT share non-prod EKS/RDS infrastructure but are isolated by
namespace, DNS host, Kubernetes secret, logical database, and database role.
Production uses separate EKS and Multi-AZ RDS.

## Git-Driven Automation

Repository prerequisites:

- Set `AWS_ROLE_ARN` to the EKS deploy role used for ECR pushes, kubeconfig, and
  Helm deploys.
- Set `AWS_TERRAFORM_ROLE_ARN` to a Terraform-capable role with S3 state,
  DynamoDB lock, and AWS infrastructure permissions.
- Set `EKS_DEPLOYMENTS_ENABLED=true` only after runtime secrets are configured:
  `INTERNAL_API_KEY`, `SESSION_SECRET`, JWT keys, OAuth client credentials, and
  `HF_TOKEN` if inference needs it.
- Set `TERRAFORM_APPLY_ENABLED=true` only after `AWS_TERRAFORM_ROLE_ARN` can
  read `samosachaat-terraform-state-906352610196` and lock
  `samosachaat-terraform-locks`.

- `.github/workflows/ci.yml`: PR validation, Conventional Commit linting,
  service tests, Docker build checks, Terraform validation, and Helm rendering.
- `.github/workflows/terraform-apply.yml`: applies Terraform from merged
  `terraform/**` changes. This is the Day 1 and Day 2 IaC update path.
- `.github/workflows/build-dev.yml`: builds immutable `dev-<sha>` images.
- `.github/workflows/deploy-dev.yml`: deploys the merged `dev-<sha>` image set
  to EKS dev, bootstraps the RDS logical DB, syncs secrets, reconciles DNS via
  Terraform, and runs internal plus external smoke tests.
- `.github/workflows/nightly.yml`: scheduled QA image build and QA deployment.
- `.github/workflows/promote-uat.yml`: automatically promotes merged dev images
  only after dev deployment and smoke tests pass, or promotes `RC*` QA images
  to UAT.
- `.github/workflows/release.yml`: semantic-release creates stable `v*` tags
  from Conventional Commits only after the matching UAT promotion succeeds.
- `.github/workflows/release-prod.yml`: stable `v*` tags promote the exact
  `uat-merge-<sha>` image set for the tagged commit to production with
  blue/green.
- `.github/workflows/patch-nodes.yml`: scheduled or `patch-nodes-*` tag-driven
  managed node rotation to the latest EKS optimized AMI.

There are no production `workflow_dispatch` deploys and no EC2 deployment
workflow. Git tags, merges, and scheduled jobs are the deployment controls.

## DNS And TLS

ACM wildcard certificates and Route53 validation records are Terraform-managed.
The ALBs are created by the AWS Load Balancer Controller after Ingress exists,
so `scripts/reconcile-route53-alias.sh` resolves the ALB DNS name and feeds it
back into Terraform. Route53 aliases remain Terraform-owned.

Non-prod uses one shared ALB group, `samosachaat-nonprod`, for
`dev`, `qa`, and `uat` hosts. Production uses `samosachaat-prod` for
`samosachaat.art` and `grafana.samosachaat.art`.

## Zero Downtime

- Blue/Green is used for production because chat streaming and auth sessions are
  state-sensitive. The candidate slot gets no public traffic until it passes
  in-cluster smoke tests.
- Deployments use `maxUnavailable: 0`, `maxSurge: 1`, readiness probes,
  preStop delay, and ALB target deregistration delay.
- QA/UAT/prod use at least two replicas per service and PDBs with
  `minAvailable: 1`.
- Pods use topology spread constraints so replicas are distributed across nodes
  when capacity allows.
- Public endpoint smoke tests verify DNS, TLS, and ALB routing after promotion.

## Day 2: Node Patching

Terraform reads the recommended AL2023 EKS optimized AMI from SSM. Applying
Terraform updates the managed node group launch template, and EKS rotates nodes
while respecting PDBs.

```bash
./scripts/rotate-nodes.sh uat --yes
./scripts/rotate-nodes.sh prod --yes
```

The scheduled GitHub workflow does the same with `.github/workflows/patch-nodes.yml`.

## Day 2: Schema Changes

Schema changes are Alembic migrations run as Helm pre-install/pre-upgrade Jobs.
The demonstration migration, `004_add_favorited.py`, is an expand-only change:
it adds a nullable-compatible/defaulted column that old pods ignore and new pods
can use after rollout.

```bash
./scripts/demo-schema-change.sh samosachaat-uat
./scripts/demo-schema-change.sh samosachaat-prod blue
```

For future risky changes, use expand/contract: add backward-compatible schema,
deploy code that writes both forms, backfill, then remove old fields in a later
release.

## Observability And Chaos Defense

Grafana is exposed at `https://grafana.samosachaat.art` through the production
ALB and allows GitHub OAuth only. Basic auth and anonymous auth are disabled.

Dashboards:

- Node Health: CPU, memory, disk, network, pods per node.
- Application Performance: request rate, latency, errors, uptime.
- Inference Service: worker and generation metrics.
- Logs: Loki queries across frontend, auth, chat-api, and inference.

Critical resource alerts route through self-hosted Alertmanager/Grafana contact
points to Slack. The live chaos response starts in Grafana, drills into Loki by
`namespace`, `service`, or `trace_id`, then verifies Kubernetes state with
`kubectl get events`, rollout status, and pod logs.

## Presentation Rule

Use [presentation-defense-checklist.md](presentation-defense-checklist.md) as
the live narration guide. Long Terraform/node-rotation recordings may be silent
video only; the decisions, checks, and recovery logic should be narrated live.
