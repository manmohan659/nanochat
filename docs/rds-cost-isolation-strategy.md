# RDS Cost-Aware Isolation Strategy

The final grading architecture deliberately uses two physical AWS RDS PostgreSQL
instances:

- `samosachaat-nonprod-pg`: shared by dev, nightly QA, and UAT.
- `samosachaat-prod-pg`: dedicated to production.

This satisfies the assignment requirement that EKS uses AWS RDS only while
avoiding separate physical RDS instances for dev, QA, and UAT.

## Isolation Model

Non-prod uses logical isolation inside one private RDS instance. QA is a
cost-aware nightly gate, so it runs lighter replica/resource settings than UAT
while still exercising the same frontend/auth/chat-api/inference service graph.

| Runtime | EKS target | Namespace | Database | App role |
| --- | --- | --- | --- | --- |
| dev | `samosachaat-dev-eks` | `samosachaat-dev` | `samosachaat_dev` | `samosachaat_dev_app` |
| QA | `samosachaat-dev-eks` | `samosachaat-qa` | `samosachaat_qa` | `samosachaat_qa_app` |
| UAT | `samosachaat-dev-eks` | `samosachaat-uat` | `samosachaat_uat` | `samosachaat_uat_app` |

Production uses physical isolation:

| Runtime | EKS target | Namespace | RDS instance | Database | App role |
| --- | --- | --- | --- | --- | --- |
| prod | `samosachaat-prod-eks` | `samosachaat-prod` | `samosachaat-prod-pg` | `samosachaat_prod` | `samosachaat_prod_app` |

Each namespace receives its own Kubernetes `samosachaat-secrets` value for
`DATABASE_URL`, so app pods connect only to their assigned database and app
role. The `scripts/bootstrap-rds-logical-db.sh` job creates or updates the
database and role from inside the EKS VPC before Helm runs Alembic migrations.

## Why Non-Prod Shares One Cluster/VPC

The previous dev and UAT VPCs both used `10.0.0.0/16`, so private cross-VPC RDS
sharing would require destructive CIDR replacement or public RDS access. The
cost-aware design keeps RDS private and avoids public database exposure by
placing dev, QA, and UAT as separate namespaces in the shared non-prod EKS/VPC.

## Terraform Ownership

- `terraform/environments/dev` owns the shared non-prod VPC, EKS, IAM, ECR, and
  `samosachaat-nonprod-pg`.
- `terraform/environments/prod` owns the production VPC, EKS, IAM, and
  `samosachaat-prod-pg`.
- `terraform/environments/uat` no longer declares a physical RDS instance; UAT
  runtime deploys to the shared non-prod cluster namespace.

The old separate UAT RDS (`samosachaat-uat-pg`) still exists from the earlier
migration path. It must be snapshotted and deleted before `samosachaat-prod-pg`
can be created while honoring the two-RDS cost-control decision, because the
account is already using the two allowed active RDS instances for this project.
Do not delete it without explicit approval; the safe decommission path is:

```bash
AWS_PROFILE=accmanmohanusfca aws rds create-db-snapshot \
  --db-instance-identifier samosachaat-uat-pg \
  --db-snapshot-identifier samosachaat-uat-pg-pre-nonprod-$(date -u +%Y%m%d%H%M%S) \
  --region us-west-2

AWS_PROFILE=accmanmohanusfca aws rds wait db-snapshot-completed \
  --db-snapshot-identifier <snapshot-id> \
  --region us-west-2

AWS_PROFILE=accmanmohanusfca terraform -chdir=terraform/environments/uat apply \
  -var=github_actions_role_arn=arn:aws:iam::906352610196:role/samosachaat-dev-github-actions
```

## Operational Commands

```bash
./deploy.sh eks dev
./deploy.sh eks qa
./deploy.sh eks uat
./deploy.sh eks prod
```

Day 2 node rotation follows the physical infrastructure tier:

```bash
./scripts/rotate-nodes.sh uat --yes   # rotates shared non-prod nodes
./scripts/rotate-nodes.sh prod --yes  # rotates prod nodes
```
