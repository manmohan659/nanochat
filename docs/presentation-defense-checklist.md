# Presentation Defense Checklist

Use this as the live narration outline. Long-running terminal output may be
recorded as silent video, but the explanation should happen live.

## Day 1 Provisioning

- Show the branch and commit being deployed.
- Show Terraform remote state in S3/DynamoDB from `terraform/bootstrap`.
- Show `terraform-apply.yml` applying shared non-prod, UAT metadata, and prod.
- Explain that VPC, EKS, RDS, ECR, IAM, ACM, Route53, EFS, and access entries are
  Terraform-owned.
- Show Route53 aliases reconciled by `scripts/reconcile-route53-alias.sh`, not
  by AWS Console edits.

## Git-Driven Promotion

- Merge to `master` builds immutable `dev-<sha>` images.
- Dev deploy must pass internal and public smoke tests before UAT promotion.
- `RC*` tags promote the current QA image stream to UAT.
- Stable `vX.Y.Z` tags are created only after UAT succeeds.
- Prod promotes the exact `uat-merge-<sha>` image set for the tag and performs a
  blue/green slot swap.

## Day 2 Node Patching

Run:

```bash
./scripts/rotate-nodes.sh uat --yes --watch
```

Explain that Terraform reads the latest EKS optimized AL2023 AMI from SSM, the
managed node group rolls forward, and Kubernetes readiness probes plus PDBs keep
at least one replica per service available during drain.

## Day 2 Schema Change

Run:

```bash
./scripts/demo-schema-change.sh samosachaat-uat
```

Explain that Alembic runs as a Helm pre-install/pre-upgrade hook. The demo
migration is expand-only, so old pods tolerate the schema and new pods begin
using it after rollout. For destructive changes, use expand/backfill/contract in
separate releases.

## Observability

- Open `https://grafana.samosachaat.art` and authenticate with GitHub OAuth.
- Show basic auth and anonymous auth disabled in `helm/observability/values.yaml`.
- Show Node Health for CPU, memory, and disk.
- Show Loki Logs dashboard filtered by namespace and service.
- Show Alertmanager/Grafana Slack contact points for critical thresholds.

## Chaos Defense

Start with Grafana, then Loki, then Kubernetes state:

```bash
kubectl get pods -n samosachaat-prod -o wide
kubectl get events -n samosachaat-prod --sort-by='.lastTimestamp'
kubectl rollout status deploy/chat-api -n samosachaat-prod
```

Use [docs/chaos-runbook.md](chaos-runbook.md) for the exact failure scenarios,
queries, and recovery commands.
