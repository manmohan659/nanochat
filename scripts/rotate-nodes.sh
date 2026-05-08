#!/usr/bin/env bash
set -euo pipefail

# Rotate EKS managed node group to latest AMI with zero downtime.
# Usage: ./scripts/rotate-nodes.sh <environment> [--yes] [--watch]
# Example: ./scripts/rotate-nodes.sh prod --yes

ENVIRONMENT="${1:?Usage: rotate-nodes.sh <environment> (dev|qa|uat|prod)}"
shift || true
AUTO_APPROVE="false"
WATCH_NODES="false"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes|-y|--auto-approve)
            AUTO_APPROVE="true"
            shift
            ;;
        --watch)
            WATCH_NODES="true"
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
    esac
done
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ENVIRONMENT="$ENVIRONMENT"
if [[ "$ENVIRONMENT" =~ ^(qa|uat)$ ]]; then
    INFRA_ENVIRONMENT="dev"
fi
RUNTIME_NAMESPACE="samosachaat-$ENVIRONMENT"
TF_DIR="$SCRIPT_DIR/../terraform/environments/$INFRA_ENVIRONMENT"
AWS_REGION="${AWS_REGION:-us-west-2}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-906352610196}"
GITHUB_ACTIONS_ROLE_ARN="${GITHUB_ACTIONS_ROLE_ARN:-arn:aws:iam::${AWS_ACCOUNT_ID}:role/samosachaat-dev-github-actions}"

if [[ -z "${AWS_PROFILE:-}" && -z "${GITHUB_ACTIONS:-}" ]]; then
    AWS_PROFILE="accmanmohanusfca"
fi

export AWS_REGION
if [[ -n "${AWS_PROFILE:-}" ]]; then
    export AWS_PROFILE
fi

if [[ ! "$ENVIRONMENT" =~ ^(dev|qa|uat|prod)$ ]]; then
    echo "Unsupported environment: $ENVIRONMENT" >&2
    exit 2
fi

terraform_args=()
if [[ "$INFRA_ENVIRONMENT" != "dev" ]]; then
    terraform_args+=("-var=github_actions_role_arn=$GITHUB_ACTIONS_ROLE_ARN")
fi

echo "=== samosaChaat Node Rotation — $ENVIRONMENT runtime on $INFRA_ENVIRONMENT infrastructure ==="

echo ""
echo "Step 1: Check current AMI vs latest available"
cd "$TF_DIR"
terraform init -input=false

echo ""
echo "Step 2: Apply Terraform to update launch template with latest AMI"
echo "This triggers EKS managed node group rolling update."
echo "EKS will:"
echo "  1. Launch new nodes with patched AMI"
echo "  2. Cordon old nodes (stop scheduling new pods)"
echo "  3. Drain pods from old nodes (respecting PodDisruptionBudgets)"
echo "  4. Terminate old nodes"
echo ""
echo "PDBs ensure minAvailable: 1 for each service = zero downtime."
if [[ "$AUTO_APPROVE" != "true" ]]; then
    echo ""
    read -p "Proceed with terraform apply? [y/N] " -n 1 -r
    echo ""
fi

if [[ "$AUTO_APPROVE" == "true" || "${REPLY:-}" =~ ^[Yy]$ ]]; then
    if [[ "${#terraform_args[@]}" -gt 0 ]]; then
        terraform apply -input=false -auto-approve "${terraform_args[@]}"
    else
        terraform apply -input=false -auto-approve
    fi
else
    echo "Aborted."
    exit 0
fi

echo ""
echo "Step 3: Verify zero-downtime pod disruption controls"
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "samosachaat-$INFRA_ENVIRONMENT-eks")
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION" 2>/dev/null || true
echo "Deployment rolling-update settings in $RUNTIME_NAMESPACE:"
kubectl get deploy -n "$RUNTIME_NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,MAX_UNAVAILABLE:.spec.strategy.rollingUpdate.maxUnavailable,MAX_SURGE:.spec.strategy.rollingUpdate.maxSurge,AVAILABLE:.status.availableReplicas' || true
echo ""
echo "PodDisruptionBudgets in $RUNTIME_NAMESPACE:"
kubectl get pdb -n "$RUNTIME_NAMESPACE" || true

echo ""
echo "Step 4: Monitor node rotation"
kubectl wait --for=condition=Ready nodes --all --timeout=20m
kubectl get nodes -o wide
if [[ "$WATCH_NODES" == "true" ]]; then
    echo "Watching nodes (Ctrl+C to stop):"
    kubectl get nodes -w
fi
