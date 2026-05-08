# Terraform

Environment and module scaffolding for the samosaChaat AWS platform.

- `environments/` holds infrastructure stacks for shared `dev`/non-prod,
  UAT metadata, and `prod`
- `modules/` holds reusable building blocks for shared infrastructure

## RDS cost model

The final platform intentionally uses two physical RDS PostgreSQL instances:

- `samosachaat-nonprod-pg`, owned by `environments/dev`, with logical databases
  `samosachaat_dev`, `samosachaat_qa`, and `samosachaat_uat`.
- `samosachaat-prod-pg`, owned by `environments/prod`, with
  `samosachaat_prod`.

UAT runtime deploys to namespace `samosachaat-uat` on the shared non-prod EKS
cluster. It does not own a separate physical RDS instance.

The UAT Terraform stack no longer declares standalone VPC, EKS, or RDS
resources. It reads the shared non-prod Terraform state and exposes UAT-specific
metadata so deployments stay tied to Terraform without carrying dead
infrastructure definitions.

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

Prod defaults to a single NAT gateway to keep the assignment account within the
expected public IPv4 and NAT cost envelope. Increase the EIP quota and set
`single_nat_gateway=false` if the defense requires one NAT gateway per AZ.

EKS defaults to Kubernetes `1.34` with AL2023 managed-node AMIs. AWS no longer
offers the previous `1.29` control-plane version in `us-west-2`.
