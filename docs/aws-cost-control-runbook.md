# AWS Cost Control Runbook

This repo supports a reversible sleep workflow for the samosaChaat AWS demo.
The goal is to stop the high-cost runtime while preserving Terraform state,
container images, DNS configuration, database data, and restore paths.

## Cost Tiers

### Sleep Mode

Use this between work sessions or overnight:

```bash
./scripts/aws-cost-down.sh sleep --yes
```

What it does:

- Uninstalls samosaChaat and observability Helm releases so Kubernetes-managed
  ALBs are deleted.
- Scales every `samosachaat-*` EKS managed node group to `min=0, desired=0`.
- Stops `samosachaat-*` RDS instances.
- Leaves the EC2 fallback running unless `--include-ec2` is passed.
- Saves previous node group sizes under `.aws-cost/nodegroups/`.

What it keeps:

- Terraform state in S3/DynamoDB.
- ECR images.
- Route53 hosted zone and ACM certificate resources.
- RDS storage and snapshots.
- EKS control planes.
- VPCs, subnets, security groups, EFS, and NAT Gateways.

Remaining cost in sleep mode:

- EKS control-plane hourly cost.
- NAT Gateway hourly cost while NAT Gateways exist.
- RDS storage and backup storage.
- Public IPv4/EIP charges, including the EC2 fallback EIP.
- Route53 hosted zone cost.

To also stop the EC2 fallback:

```bash
./scripts/aws-cost-down.sh sleep --include-ec2 --yes
```

Stopping the EC2 fallback takes `https://samosachaat.art` offline while GoDaddy
still points to `16.148.217.62`, but it does not delete the instance or EIP.

## Start Back Up

Start RDS and restore node group sizes:

```bash
./scripts/aws-cost-up.sh --yes
```

If the EC2 fallback was stopped:

```bash
./scripts/aws-cost-up.sh --include-ec2 --yes
```

If Helm releases were removed and namespace secrets still exist, restore the
dev/QA/UAT app releases:

```bash
./scripts/aws-cost-up.sh --restore-apps --yes
```

If namespace secrets were deleted, use the normal deployment path with real
runtime secrets loaded in the shell:

```bash
./deploy.sh eks dev
./deploy.sh eks qa
./deploy.sh eks uat
```

## Status

Inspect cost-bearing resources:

```bash
./scripts/aws-cost-status.sh
```

This reports:

- RDS instance status.
- EC2 fallback state.
- NAT Gateways.
- Elastic IPs/public IPv4s.
- Kubernetes-managed ALBs.
- EKS clusters, node groups, nodes, and Helm releases.

## Near-Zero Cost / Hibernate

Sleep mode is safe and fast, but it is not zero-cost because EKS control planes
and NAT Gateways cannot be paused. Near-zero cost requires deleting runtime
infrastructure and recreating it later through Terraform.

Do not automate hibernate casually because the current dev Terraform state owns
`samosachaat-nonprod-pg`. A careless `terraform destroy` would delete database
resources unless the stack is first refactored or targeted very carefully.

Safe hibernate design, if needed later:

1. Create final RDS snapshots.
2. Stop or snapshot/delete nonessential RDS instances only after explicit
   approval.
3. Remove Helm releases and wait for ALBs to delete.
4. Destroy only EKS/node/ALB/NAT runtime resources, preserving Terraform state,
   ECR, Route53, ACM definitions, RDS snapshots, and any approved DB snapshots.
5. Recreate through Terraform apply and redeploy Helm.

For the current assignment, use sleep mode for day-to-day cost control and keep
hibernate as a deliberate manual maintenance operation.

## AWS Service Notes

- RDS stopped instances can be automatically restarted by AWS after seven days;
  rerun `aws-cost-down.sh` if that happens before the next demo session.
- Public IPv4 addresses are billed whether attached or idle, so retaining the
  fallback EIP still has a small hourly cost.
- Deleting ALBs requires the AWS Load Balancer Controller to be running, so the
  script removes Helm releases before scaling nodes to zero.
