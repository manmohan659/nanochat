#!/usr/bin/env bash
set -euo pipefail

# Resolve the AWS Load Balancer Controller ALB for a runtime environment and
# feed it back into Terraform so Route53 aliases stay Terraform-owned.
#
# Usage: ./scripts/reconcile-route53-alias.sh <dev|qa|uat|prod>

ENVIRONMENT="${1:?Usage: reconcile-route53-alias.sh <dev|qa|uat|prod>}"
if [[ ! "$ENVIRONMENT" =~ ^(dev|qa|uat|prod)$ ]]; then
  echo "Unsupported environment: $ENVIRONMENT" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
AWS_REGION="${AWS_REGION:-us-west-2}"
NAMESPACE="samosachaat-${ENVIRONMENT}"
INFRA_ENV="$ENVIRONMENT"
ALB_STACK_NAME="samosachaat-prod"

if [[ "$ENVIRONMENT" =~ ^(dev|qa|uat)$ ]]; then
  INFRA_ENV="dev"
  ALB_STACK_NAME="samosachaat-nonprod"
fi

TF_DIR="${ROOT_DIR}/terraform/environments/${INFRA_ENV}"

ALB_HOST=""
for _ in $(seq 1 40); do
  ALB_HOST="$(kubectl get ingress samosachaat -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  if [[ -n "$ALB_HOST" ]]; then
    break
  fi
  sleep 15
done

if [[ -z "$ALB_HOST" ]]; then
  ALB_ARN="$(aws resourcegroupstaggingapi get-resources \
    --region "$AWS_REGION" \
    --resource-type-filters elasticloadbalancing:loadbalancer \
    --tag-filters "Key=ingress.k8s.aws/stack,Values=${ALB_STACK_NAME}" \
    --query 'ResourceTagMappingList[0].ResourceARN' \
    --output text 2>/dev/null || true)"
  if [[ -n "$ALB_ARN" && "$ALB_ARN" != "None" ]]; then
    ALB_HOST="$(aws elbv2 describe-load-balancers \
      --region "$AWS_REGION" \
      --load-balancer-arns "$ALB_ARN" \
      --query 'LoadBalancers[0].DNSName' \
      --output text)"
  fi
fi

if [[ -z "$ALB_HOST" || "$ALB_HOST" == "None" ]]; then
  echo "Could not resolve ALB hostname for $ENVIRONMENT" >&2
  exit 1
fi

ALB_LOOKUP="${ALB_HOST#dualstack.}"
ALB_ZONE_ID="$(aws elbv2 describe-load-balancers \
  --region "$AWS_REGION" \
  --query "LoadBalancers[?DNSName=='${ALB_LOOKUP}'].CanonicalHostedZoneId | [0]" \
  --output text)"

if [[ -z "$ALB_ZONE_ID" || "$ALB_ZONE_ID" == "None" ]]; then
  echo "Could not resolve ALB hosted-zone ID for $ALB_LOOKUP" >&2
  exit 1
fi

terraform_args=(-input=false -auto-approve "-var=alb_dns_name=${ALB_LOOKUP}" "-var=alb_zone_id=${ALB_ZONE_ID}")
if [[ "$INFRA_ENV" == "prod" && -n "${GITHUB_ACTIONS_ROLE_ARN:-}" ]]; then
  terraform_args+=("-var=github_actions_role_arn=${GITHUB_ACTIONS_ROLE_ARN}")
fi

terraform -chdir="$TF_DIR" init -input=false >/dev/null
terraform -chdir="$TF_DIR" apply "${terraform_args[@]}"

echo "Route53 aliases reconciled for $ENVIRONMENT via $ALB_LOOKUP"
