#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/aws-cost-lib.sh
source "${SCRIPT_DIR}/aws-cost-lib.sh"

MODE="${1:-sleep}"
AUTO_APPROVE="false"
SKIP_HELM="false"
SKIP_NODES="false"
SKIP_RDS="false"
WAIT_FOR_RDS="true"

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/aws-cost-down.sh sleep [--yes] [--skip-helm] [--skip-nodes] [--skip-rds]

Sleep mode is reversible and keeps durable state:
  - uninstall samosaChaat/observability Helm releases so ALBs are deleted
  - scale EKS managed node groups to desired/min 0
  - stop samosaChaat RDS instances

It does not delete Terraform state, ECR images, Route53, ACM, snapshots, RDS storage,
EKS control planes, or VPCs.
USAGE
}

shift_args=()
if [[ "$MODE" == "-h" || "$MODE" == "--help" ]]; then
  usage
  exit 0
fi
if [[ "$MODE" != "sleep" ]]; then
  err "Unsupported mode: $MODE. Only sleep is implemented as an automated non-destructive mode."
  usage
  exit 2
fi
shift || true
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --yes|-y) AUTO_APPROVE="true" ;;
    --skip-helm) SKIP_HELM="true" ;;
    --skip-nodes) SKIP_NODES="true" ;;
    --skip-rds) SKIP_RDS="true" ;;
    --no-wait-rds) WAIT_FOR_RDS="false" ;;
    --help|-h) usage; exit 0 ;;
    *) shift_args+=("$1") ;;
  esac
  shift
done
if [[ "${#shift_args[@]}" -gt 0 ]]; then
  err "Unknown arguments: ${shift_args[*]}"
  usage
  exit 2
fi

check_prereqs
ensure_state_dir

confirm_or_exit "$AUTO_APPROVE" "Put samosaChaat AWS runtime into sleep mode?"

clusters="$(discover_clusters || true)"

if [[ "$SKIP_HELM" != "true" ]]; then
  log "Removing runtime Helm releases before scaling nodes down."
  if [[ -z "$clusters" ]]; then
    warn "No EKS clusters found."
  else
    while IFS= read -r cluster; do
      [[ -z "$cluster" ]] && continue
      log "Cluster ${cluster}: removing Helm releases."
      if ! kubeconfig_for_cluster "$cluster"; then
        warn "Could not configure kubeconfig for ${cluster}; skipping Helm cleanup."
        continue
      fi
      namespaces="$(samosachaat_namespaces)"
      if [[ -z "$namespaces" ]]; then
        log "Cluster ${cluster}: no samosaChaat namespaces."
        continue
      fi
      while IFS= read -r ns; do
        [[ -z "$ns" ]] && continue
        releases="$(helm list -n "$ns" -q 2>/dev/null || true)"
        if [[ -z "$releases" ]]; then
          log "Namespace ${ns}: no Helm releases."
          continue
        fi
        while IFS= read -r release; do
          [[ -z "$release" ]] && continue
          log "Uninstalling ${release} in ${ns}."
          helm uninstall "$release" -n "$ns" --wait --timeout 5m 2>/dev/null || warn "Helm uninstall failed for ${release} in ${ns}; continuing."
        done <<< "$releases"
      done <<< "$namespaces"
    done <<< "$clusters"
  fi

  log "Waiting briefly for AWS Load Balancer Controller to delete ALBs."
  for _ in $(seq 1 20); do
    remaining="$(count_samosachaat_albs)"
    if [[ "$remaining" == "0" ]]; then
      log "No Kubernetes-managed samosaChaat ALBs remain."
      break
    fi
    log "Waiting for ${remaining} ALB(s) to disappear..."
    sleep 15
  done
fi

if [[ "$SKIP_NODES" != "true" ]]; then
  log "Scaling EKS managed node groups to zero."
  if [[ -z "$clusters" ]]; then
    warn "No EKS clusters found."
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
        save_nodegroup_scaling "$cluster" "$nodegroup"
        max_size="$(jq -r '.maxSize // 1' "$(nodegroup_state_file "$cluster" "$nodegroup")")"
        if [[ "$max_size" -lt 1 ]]; then
          max_size=1
        fi
        log "Scaling ${cluster}/${nodegroup} to min=0 desired=0 max=${max_size}."
        aws eks update-nodegroup-config \
          --region "$AWS_REGION" \
          --cluster-name "$cluster" \
          --nodegroup-name "$nodegroup" \
          --scaling-config "minSize=0,desiredSize=0,maxSize=${max_size}" >/dev/null
        aws eks wait nodegroup-active \
          --region "$AWS_REGION" \
          --cluster-name "$cluster" \
          --nodegroup-name "$nodegroup"
      done <<< "$nodegroups"
      log "Waiting for ${cluster} worker EC2 instances to terminate."
      wait_for_eks_workers_gone "$cluster" || true
    done <<< "$clusters"
  fi
fi

if [[ "$SKIP_RDS" != "true" ]]; then
  log "Stopping samosaChaat RDS instances. AWS may auto-start stopped RDS after 7 days."
  while read -r db status; do
    [[ -z "${db:-}" ]] && continue
    case "$status" in
      available)
        log "Stopping RDS ${db}."
        aws rds stop-db-instance \
          --region "$AWS_REGION" \
          --db-instance-identifier "$db" >/dev/null
        ;;
      stopped|stopping)
        log "RDS ${db} is already ${status}."
        ;;
      *)
        warn "RDS ${db} is ${status}; not stopping from this state."
        ;;
    esac
  done < <(rds_instances)

  if [[ "$WAIT_FOR_RDS" == "true" ]]; then
    while read -r db _status; do
      [[ -z "${db:-}" ]] && continue
      log "Waiting for RDS ${db} to stop."
      wait_for_rds_status "$db" "stopped" || true
    done < <(rds_instances)
  fi
fi

log "Sleep mode complete. Run ./scripts/aws-cost-up.sh --yes to start RDS and nodes again."
