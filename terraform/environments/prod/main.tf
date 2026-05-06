locals {
  name_prefix  = "samosachaat-${var.environment}"
  cluster_name = "${local.name_prefix}-eks"

  tags = {
    Project     = "samosachaat"
    Environment = var.environment
  }
}

module "vpc" {
  source = "../../modules/vpc"

  name               = local.name_prefix
  cluster_name       = local.cluster_name
  cidr               = "10.0.0.0/16"
  azs                = ["us-west-2a", "us-west-2b", "us-west-2c"]
  private_subnets    = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  single_nat_gateway = false
  tags               = local.tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name       = local.cluster_name
  cluster_version    = "1.29"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  node_instance_type = "t3.xlarge"
  node_min_size      = 3
  node_max_size      = 10
  node_desired_size  = 3

  tags = local.tags
}

module "ecr" {
  source = "../../modules/ecr"

  force_delete = false
  tags         = local.tags
}

module "iam" {
  source = "../../modules/iam"

  name_prefix       = local.name_prefix
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  # GitHub OIDC provider is created by the dev env (account-level resource).
  create_github_oidc  = false
  github_repositories = var.github_repositories
  tags                = local.tags
}

resource "aws_eks_access_entry" "github_actions" {
  count = var.github_actions_role_arn == "" ? 0 : 1

  cluster_name  = module.eks.cluster_name
  principal_arn = var.github_actions_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "github_actions_admin" {
  count = var.github_actions_role_arn == "" ? 0 : 1

  cluster_name  = module.eks.cluster_name
  principal_arn = var.github_actions_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.github_actions]
}

module "rds" {
  source = "../../modules/rds"

  identifier                 = "${local.name_prefix}-pg"
  vpc_id                     = module.vpc.vpc_id
  private_subnet_ids         = module.vpc.private_subnet_ids
  eks_node_security_group_id = module.eks.node_security_group_id

  instance_class      = "db.t3.medium"
  multi_az            = true
  skip_final_snapshot = false
  deletion_protection = true

  tags = local.tags
}

module "efs" {
  source = "../../modules/efs"

  name                       = "${local.name_prefix}-models"
  vpc_id                     = module.vpc.vpc_id
  private_subnet_ids         = module.vpc.private_subnet_ids
  eks_node_security_group_id = module.eks.node_security_group_id

  tags = local.tags
}

module "acm" {
  source = "../../modules/acm"

  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  wait_for_validation       = false

  tags = local.tags
}

module "route53" {
  source = "../../modules/route53"

  domain_name              = var.domain_name
  create_zone              = var.create_route53_zone
  subdomains               = ["grafana"]
  acm_validation_records   = module.acm.validation_records
  acm_certificate_arn      = module.acm.certificate_arn
  validate_acm_certificate = var.validate_acm_certificate
  alb_dns_name             = var.alb_dns_name
  alb_zone_id              = var.alb_zone_id
}
