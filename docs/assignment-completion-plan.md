# samosaChaat Assignment Completion Plan

This is the grading path for moving the current EC2 demo into the required EKS + RDS + Terraform + Git-driven platform.

## Target Architecture

- Frontend: Next.js service behind AWS ALB Ingress at `https://samosachaat.art`.
- Backend microservices on EKS:
  - `auth` FastAPI OAuth/JWT service.
  - `chat-api` FastAPI conversation/SSE orchestration service.
  - `inference` FastAPI model service or proxy.
- Database: AWS RDS PostgreSQL only for EKS environments. No in-cluster PostgreSQL and no EC2 PostgreSQL for the final demo.
- Observability: self-hosted `kube-prometheus-stack` + Grafana + Alertmanager + Loki/Promtail on EKS.
- CI/CD: GitHub Actions with AWS OIDC. No AWS Console deploy clicks.

## One-Time Prerequisites

1. Confirm AWS account and region:

```bash
aws sts get-caller-identity
export AWS_REGION=us-west-2
```

2. Bootstrap Terraform remote state with Terraform:

```bash
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap apply
```

3. Delegate DNS to Route53.

Run the first Terraform apply for the environment that will own DNS, then copy `route53_name_servers` into GoDaddy name servers for `samosachaat.art`.

```bash
terraform -chdir=terraform/environments/prod init
terraform -chdir=terraform/environments/prod apply
terraform -chdir=terraform/environments/prod output route53_name_servers
```

After GoDaddy delegation propagates, validate ACM:

```bash
terraform -chdir=terraform/environments/prod apply -var=validate_acm_certificate=true
```

4. Export runtime secrets before EKS deployment:

```bash
export GOOGLE_CLIENT_ID=...
export GOOGLE_CLIENT_SECRET=...
export GITHUB_CLIENT_ID=...
export GITHUB_CLIENT_SECRET=...
export GITHUB_GRAFANA_CLIENT_ID=...
export GITHUB_GRAFANA_CLIENT_SECRET=...
export GOOGLE_GRAFANA_CLIENT_ID=...
export GOOGLE_GRAFANA_CLIENT_SECRET=...
export SLACK_WEBHOOK_URL=...
export INFERENCE_SERVICE_URL=...
```

Optional but recommended: set stable JWT key files instead of allowing `deploy.sh` to generate demo keys.

```bash
./scripts/generate-jwt-keys.sh
export JWT_PRIVATE_KEY_FILE=.secrets/jwt-private.pem
export JWT_PUBLIC_KEY_FILE=.secrets/jwt-public.pem
```

5. Configure GitHub repository secrets and variables:

- `AWS_ROLE_ARN`: GitHub Actions OIDC role created by Terraform.
- `AWS_REGION`: `us-west-2`.
- `SEMANTIC_RELEASE_TOKEN` or `INFRA_REPO_PAT`: GitHub PAT used by semantic-release so generated `v*` tags trigger the production deployment workflow.
- OAuth, Grafana OAuth, Slack, and runtime secrets used by `deploy.sh` and Helm secrets.

## Day 1 Provisioning

Provision each environment through Terraform and Helm:

```bash
./deploy.sh eks dev
./deploy.sh eks uat
./deploy.sh eks prod
```

For UAT/prod, `deploy.sh` automatically reuses the GitHub Actions role created by the dev environment. If needed, pass it explicitly:

```bash
export GITHUB_ACTIONS_ROLE_ARN="$(terraform -chdir=terraform/environments/dev output -raw github_actions_role_arn)"
./deploy.sh eks uat
./deploy.sh eks prod
```

After prod deploy, verify:

```bash
kubectl get nodes
kubectl get pods -n samosachaat-prod
kubectl get ingress -n samosachaat-prod
curl -Ik https://samosachaat.art
curl -Ik https://grafana.samosachaat.art
```

## CI/CD Promotion Flow

The GitHub Actions layout follows the same control pattern used in the SiPeKa repos: PR validation first, exact image tags for promotion, automated release creation from Conventional Commits, and smoke tests before each environment is considered promoted.

1. PR checks:
   - `.github/workflows/ci.yml` enforces Conventional Commits with commitlint.
   - Service tests run only for changed paths.
   - Docker images build locally in CI before a merge is allowed.
   - Terraform environments validate when IaC files change.

2. Dev build:
   - Merge to `master` or `main`.
   - `.github/workflows/build-dev.yml` builds and pushes `dev-<sha>` and `dev-latest`.
   - `.github/workflows/deploy-ec2.yml` remains for the old EC2 fallback, not the final grading path.

3. Nightly QA:
   - `.github/workflows/nightly.yml` runs on schedule or manually.
   - Builds `qa-<sha>` and `qa-latest`.
   - Deploys to `samosachaat-qa` namespace on the QA cluster.
   - Runs `scripts/smoke-test-k8s.sh samosachaat-qa` across frontend, auth, chat-api, and inference.

4. Dev/QA to UAT:
   - PR merge path: successful `.github/workflows/build-dev.yml` completion promotes the exact `dev-<sha>` image set to UAT as `uat-merge-<sha>`.
   - RC path: pushing an `RC*` tag promotes the latest smoke-tested `qa-latest` image set as `uat-RC*`.
   - Manual recovery path: `workflow_dispatch` can promote a specific source tag such as `qa-<sha>` or `dev-<sha>`.
   - Helm deploys UAT with `--wait`, then `scripts/smoke-test-k8s.sh samosachaat-uat` gates success.

```bash
git tag RC1
git push origin RC1
```

5. Release creation:
   - `.github/workflows/release.yml` runs semantic-release from Conventional Commits.
   - semantic-release updates `CHANGELOG.md`, creates the GitHub release, and pushes `v*` release tags.
   - Use `SEMANTIC_RELEASE_TOKEN` or `INFRA_REPO_PAT`; the default GitHub token will not trigger downstream workflows from a generated tag.

6. UAT to production:
   - Push a release tag such as `v1.0.1`, or let semantic-release create it.
   - Prerelease tags such as `v1.0.1-rc.1` are excluded from the production workflow.
   - `.github/workflows/release-prod.yml` promotes the latest consistent `uat-*` image set to `prod-v1.0.1`.
   - Prod uses Blue/Green: deploy inactive slot, smoke test all services, then swap only the ALB Ingress target.

```bash
git tag v1.0.1
git push origin v1.0.1
```

## Blue/Green Justification

Blue/Green is the best fit for this project because chat streaming and auth flows are state-sensitive. A canary would deliberately send a slice of live users through a partially proven release, which is useful for very high-traffic systems but harder to defend in a class demo. Blue/Green gives a simple recovery story:

- Green is deployed without public traffic.
- Green is smoke-tested inside the cluster.
- The ALB Ingress switches traffic atomically to Green.
- Blue remains available as rollback standby.

Zero dropped requests are supported by:

- Kubernetes readiness probes.
- `maxUnavailable: 0` rolling update strategy.
- PodDisruptionBudgets in QA/UAT/prod.
- ALB target deregistration delay.
- At least two replicas in QA/UAT and three replicas in prod.

## Day 2 OS/Security Patching Demo

The EKS managed node group reads the latest EKS-optimized AMI ID from SSM. Re-running Terraform updates the launch template and triggers managed node rotation.

```bash
./scripts/rotate-nodes.sh prod
```

Narration points:

- Terraform detects the latest patched AMI.
- EKS launches replacement nodes first.
- Kubernetes cordons and drains old nodes.
- PDBs keep at least one pod per service available.
- Readiness probes prevent traffic to unready pods.

Watch during the demo:

```bash
kubectl get nodes -w
kubectl get pods -n samosachaat-prod -o wide -w
```

## Day 2 Schema Change Demo

Migration `004_add_favorited.py` adds `conversations.is_favorited`.

```bash
./scripts/demo-schema-change.sh samosachaat-prod
```

Narration points:

- The app uses Alembic, not manual SQL in the console.
- The Helm pre-upgrade hook runs `alembic -c db/alembic.ini upgrade head`.
- The change is backward-compatible: adding a nullable/defaulted column first means old pods ignore it while new pods can read it.
- The model exposes `is_favorited` in API payloads after the rollout.

## Observability And Logging

Deploys inside EKS:

- Prometheus for metrics.
- Grafana for dashboards.
- Alertmanager for Slack alerts.
- Loki + Promtail for logs.

Required dashboard:

- Open `https://grafana.samosachaat.art`.
- Login through GitHub or Google OAuth only.
- Show the `Node Health` dashboard for CPU, memory, and disk.
- Show application dashboards for request rate, 5xx, latency, and inference health.

Required log query examples:

```logql
{namespace="samosachaat-prod"} | json | level="error"
{namespace="samosachaat-prod", app=~"auth|chat-api|inference"} | json
{namespace="samosachaat-prod"} | json | trace_id="<trace-id>"
```

## Chaos Defense Script

Use `docs/chaos-runbook.md` in the live defense. The default response pattern is:

1. State the symptom from Grafana.
2. Narrow the blast radius by namespace/service.
3. Query Loki for the same time window.
4. Verify Kubernetes state with `kubectl get pods/events`.
5. Explain the automatic recovery mechanism or apply the smallest safe fix.

Fast commands:

```bash
kubectl get pods -n samosachaat-prod
kubectl get events -n samosachaat-prod --sort-by=.lastTimestamp | tail -30
kubectl rollout status deploy/chat-api -n samosachaat-prod
kubectl logs -n samosachaat-prod deploy/chat-api --tail=100
```

## Final Rubric Checklist

- Terraform: VPC, EKS, RDS, ECR, IAM, ACM, Route53, EFS, and state backend are Terraform-managed.
- App/networking: 3+ microservices on EKS, RDS PostgreSQL, HTTPS custom domain, ALB Ingress.
- CI/CD: PR commitlint/tests/Docker build, dev build, nightly QA smoke test, RC/build-success to UAT, semantic-release/`v*` release to prod.
- Strategy: Blue/Green with inactive-slot smoke test and ingress swap.
- Day 2 patching: `scripts/rotate-nodes.sh`.
- Day 2 schema: Alembic Helm hook and `scripts/demo-schema-change.sh`.
- Observability: Prometheus/Grafana/Alertmanager/Loki inside EKS, Grafana OAuth, Slack alerts.
- Defense: use Grafana first, Loki second, Kubernetes events third.

## What Is Still Operationally Pending

- Run Terraform applies in AWS for dev, UAT, and prod.
- Delegate GoDaddy DNS to the Terraform-created Route53 zone and complete ACM validation.
- Configure GitHub repository secrets and environment protections.
- Create GitHub/Google OAuth apps for Grafana and app login callback URLs.
- Run one live end-to-end promotion: PR merge to UAT, RC tag to UAT, and `v*` tag to prod.
- Record the silent Day 1/Day 2 videos, then narrate over them live during the presentation.
