# Terraform

Environment and module scaffolding for the samosaChaat AWS platform.

- `environments/` holds infrastructure stacks for `dev`/non-prod, legacy `uat`
  decommission planning, and `prod`
- `modules/` holds reusable building blocks for shared infrastructure

## RDS cost model

The final platform intentionally uses two physical RDS PostgreSQL instances:

- `samosachaat-nonprod-pg`, owned by `environments/dev`, with logical databases
  `samosachaat_dev`, `samosachaat_qa`, and `samosachaat_uat`.
- `samosachaat-prod-pg`, owned by `environments/prod`, with
  `samosachaat_prod`.

UAT runtime deploys to namespace `samosachaat-uat` on the shared non-prod EKS
cluster. It does not own a separate physical RDS instance.

The legacy `samosachaat-uat-pg` instance may still exist during migration. It
must be snapshotted and removed only after explicit approval; until then the
project cannot create `samosachaat-prod-pg` without violating the two-RDS
cost-control decision because the two allowed active RDS slots are already
occupied.

## Target account backend

The migration target is AWS account `906352610196` in `us-west-2`, using the
`accmanmohanusfca` AWS CLI profile. Remote state is stored in:

- S3 bucket: `samosachaat-terraform-state-906352610196`
- DynamoDB lock table: `samosachaat-terraform-locks`

Bootstrap once before initializing the environment stacks:

```bash
AWS_PROFILE=accmanmohanusfca terraform -chdir=terraform/bootstrap init -reconfigure
AWS_PROFILE=accmanmohanusfca terraform -chdir=terraform/bootstrap apply
```

Then initialize each stack with `terraform init -reconfigure` from its
environment directory.

Prod defaults to a single NAT gateway while this account has the default
Elastic IP quota and the EC2 fallback keeps one EIP allocated.

EKS defaults to Kubernetes `1.34` with AL2023 managed-node AMIs. AWS no longer
offers the previous `1.29` control-plane version in `us-west-2`.
