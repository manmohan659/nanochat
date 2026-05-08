#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/aws-cost-lib.sh
source "${SCRIPT_DIR}/aws-cost-lib.sh"

AUTO_APPROVE="false"
RESTORE_APPS="false"
SKIP_RDS="false"
SKIP_NODES="false"

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/aws-cost-up.sh [--yes] [--restore-apps] [--skip-rds] [--skip-nodes]

Starts the reversible sleep-mode resources:
  - start stopped samosaChaat RDS instances
  - restore EKS node group sizes from .aws-cost/nodegroups/*.json
  - optionally restore dev/QA/UAT Helm app releases with --restore-apps

If you deleted clusters or VPCs manually, run Terraform apply first.
USAGE
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --yes|-y) AUTO_APPROVE="true" ;;
    --restore-apps) RESTORE_APPS="true" ;;
    --skip-rds) SKIP_RDS="true" ;;
    --skip-nodes) SKIP_NODES="true" ;;
    --help|-h) usage; exit 0 ;;
    *) err "Unknown argument: $1"; usage; exit 2 ;;
  esac
  shift
done

check_prereqs
ensure_state_dir

confirm_or_exit "$AUTO_APPROVE" "Start samosaChaat AWS runtime from sleep mode?"

if [[ "$SKIP_RDS" != "true" ]]; then
  log "Starting samosaChaat RDS instances."
  while read -r db status; do
    [[ -z "${db:-}" ]] && continue
    case "$status" in
      stopped)
        log "Starting RDS ${db}."
        aws rds start-db-instance \
          --region "$AWS_REGION" \
          --db-instance-identifier "$db" >/dev/null
        ;;
      available|starting)
        log "RDS ${db} is already ${status}."
        ;;
      *)
        warn "RDS ${db} is ${status}; not starting from this state."
        ;;
    esac
  done < <(rds_instances)

  while read -r db _status; do
    [[ -z "${db:-}" ]] && continue
    log "Waiting for RDS ${db} to become available."
    aws rds wait db-instance-available \
      --region "$AWS_REGION" \
      --db-instance-identifier "$db" || warn "Timed out waiting for ${db}."
  done < <(rds_instances)
fi

clusters="$(discover_clusters || true)"
if [[ "$SKIP_NODES" != "true" ]]; then
  log "Restoring EKS managed node group sizes."
  if [[ -z "$clusters" ]]; then
    warn "No EKS clusters found. If you hibernated by deleting clusters, run Terraform apply first."
  else
    while IFS= read -r cluster; do
      [[ -z "$cluster" ]] && continue
      nodegroups="$(discover_nodegroups "$cluster")"
      if [[ -z "$nodegroups" ]]; then
        log "Cluster ${cluster}: no node groups."
        continue
      fi
      while IFS= read -r nodegroup; do
        [[ -z "$nodegroup" ]] && continue
        scaling="$(restore_scaling_config "$cluster" "$nodegroup")"
        log "Restoring ${cluster}/${nodegroup} to ${scaling}."
        aws eks update-nodegroup-config \
          --region "$AWS_REGION" \
          --cluster-name "$cluster" \
          --nodegroup-name "$nodegroup" \
          --scaling-config "$scaling" >/dev/null
        aws eks wait nodegroup-active \
          --region "$AWS_REGION" \
          --cluster-name "$cluster" \
          --nodegroup-name "$nodegroup"
      done <<< "$nodegroups"
    done <<< "$clusters"
  fi
fi

if [[ "$RESTORE_APPS" == "true" ]]; then
  log "Restoring dev, QA, and UAT Helm app releases from existing Kubernetes secrets."
  registry="$(ecr_registry)"
  for env in dev qa uat; do
    cluster="${PROJECT_PREFIX}-dev-eks"
    namespace="${PROJECT_PREFIX}-${env}"
    values="$(app_values_file "$env")"
    cert_arn="$(acm_cert_for_env "$env")"
    if [[ ! -f "$values" ]]; then
      warn "Missing values file for ${env}: ${values}; skipping."
      continue
    fi
    kubeconfig_for_cluster "$cluster" || {
      warn "Could not configure kubeconfig for ${cluster}; skipping ${env}."
      continue
    }
    if ! kubectl get secret samosachaat-secrets -n "$namespace" >/dev/null 2>&1; then
      warn "Namespace ${namespace} has no samosachaat-secrets; run ./deploy.sh eks ${env} with runtime secrets instead."
      continue
    fi
    log "Restoring ${env} release in ${namespace}."
    helm upgrade --install samosachaat "${ROOT_DIR}/helm/samosachaat" \
      -f "$values" \
      --set global.imageRegistry="$registry" \
      --set global.imageTag="dev-latest" \
      --set ingress.acmCertArn="$cert_arn" \
      --set secrets.create=false \
      --namespace "$namespace" \
      --create-namespace \
      --wait --timeout 10m
  done
fi

log "Startup complete. Run ./scripts/aws-cost-status.sh to inspect current cost-bearing resources."
