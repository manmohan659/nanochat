# UAT

User acceptance testing is a logical runtime on shared non-prod infrastructure.

This stack intentionally does not declare standalone VPC, EKS, or RDS resources.
It reads the dev/non-prod Terraform state and exposes UAT-specific outputs used
by GitHub Actions and deployment scripts:

- cluster endpoint/name for `samosachaat-dev-eks`
- shared non-prod RDS endpoint/password
- logical database name `samosachaat_uat`
- shared ACM certificate, Route53 zone, and GitHub OIDC role
