#!/usr/bin/env bash
set -euo pipefail

# Install/upgrade Kubernetes add-ons required by the app layer. AWS
# infrastructure identities are still Terraform-owned; this script only applies
# cluster add-on Helm releases after EKS exists.
#
# Usage: ./scripts/install-cluster-addons.sh <cluster-name> <alb-controller-role-arn>

CLUSTER_NAME="${1:?Usage: install-cluster-addons.sh <cluster-name> <alb-controller-role-arn>}"
ALB_CONTROLLER_ROLE_ARN="${2:?Usage: install-cluster-addons.sh <cluster-name> <alb-controller-role-arn>}"

helm repo add eks https://aws.github.io/eks-charts >/dev/null
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null
helm repo update >/dev/null

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="${CLUSTER_NAME}" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=${ALB_CONTROLLER_ROLE_ARN}" \
  --wait --timeout 5m

helm upgrade --install metrics-server metrics-server/metrics-server \
  -n kube-system \
  --set args="{--kubelet-preferred-address-types=InternalIP\\,ExternalIP\\,Hostname,--kubelet-use-node-status-port}" \
  --wait --timeout 5m
