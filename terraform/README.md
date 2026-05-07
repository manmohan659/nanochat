# Terraform

Environment and module scaffolding for the samosaChaat AWS platform.

- `environments/` holds per-environment stacks for `dev`, `uat`, and `prod`
- `modules/` holds reusable building blocks for shared infrastructure

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
