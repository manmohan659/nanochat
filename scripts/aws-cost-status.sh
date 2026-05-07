#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/aws-cost-lib.sh
source "${SCRIPT_DIR}/aws-cost-lib.sh"

check_prereqs

log "AWS account"
aws sts get-caller-identity \
  --query '{Account:Account,Arn:Arn}' \
  --output table

echo ""
log "RDS instances"
rds_instances | awk 'BEGIN {printf "%-30s %-16s\n", "DBInstance", "Status"} {printf "%-30s %-16s\n", $1, $2}'

echo ""
log "EC2 fallback"
printf '%-24s %s\n' "$EC2_FALLBACK_INSTANCE_ID" "$(fallback_instance_state)"

echo ""
log "NAT gateways"
aws ec2 describe-nat-gateways \
  --region "$AWS_REGION" \
  --filter "Name=tag:Project,Values=${PROJECT_PREFIX}" "Name=state,Values=pending,available,deleting,deleted,failed" \
  --query 'NatGateways[].{NatGatewayId:NatGatewayId,State:State,SubnetId:SubnetId,PublicIp:NatGatewayAddresses[0].PublicIp}' \
  --output table

echo ""
log "Public IPv4 / Elastic IPs"
aws ec2 describe-addresses \
  --region "$AWS_REGION" \
  --query 'Addresses[].{PublicIp:PublicIp,AllocationId:AllocationId,InstanceId:InstanceId,AssociationId:AssociationId}' \
  --output table

echo ""
log "ALBs created by Kubernetes ingress"
aws resourcegroupstaggingapi get-resources \
  --region "$AWS_REGION" \
  --resource-type-filters elasticloadbalancing:loadbalancer \
  --tag-filters "Key=ingress.k8s.aws/stack" \
  --query 'ResourceTagMappingList[].ResourceARN' \
  --output table

echo ""
log "EKS clusters and node groups"
clusters="$(discover_clusters || true)"
if [[ -z "$clusters" ]]; then
  echo "No ${PROJECT_PREFIX}-* EKS clusters found."
else
  while IFS= read -r cluster; do
    [[ -z "$cluster" ]] && continue
    echo ""
    printf 'Cluster: %s\n' "$cluster"
    nodegroups="$(discover_nodegroups "$cluster")"
    if [[ -z "$nodegroups" ]]; then
      echo "  No node groups."
    else
      while IFS= read -r nodegroup; do
        [[ -z "$nodegroup" ]] && continue
        aws eks describe-nodegroup \
          --region "$AWS_REGION" \
          --cluster-name "$cluster" \
          --nodegroup-name "$nodegroup" \
          --query 'nodegroup.{Nodegroup:nodegroupName,Status:status,Min:scalingConfig.minSize,Desired:scalingConfig.desiredSize,Max:scalingConfig.maxSize}' \
          --output table
      done <<< "$nodegroups"
    fi
    printf '  Billable EKS worker EC2 instances visible: %s\n' "$(count_eks_worker_instances "$cluster")"

    if kubeconfig_for_cluster "$cluster" >/dev/null 2>&1; then
      echo "  Kubernetes node objects may remain briefly after scale-down; EC2 count above is the billing signal."
      kubectl get nodes 2>/dev/null || true
      helm list -A 2>/dev/null | awk 'NR == 1 || /samosachaat|observability|aws-load-balancer-controller/' || true
    fi
  done <<< "$clusters"
fi
