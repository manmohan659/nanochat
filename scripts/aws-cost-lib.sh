#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

AWS_PROFILE="${AWS_PROFILE:-accmanmohanusfca}"
AWS_REGION="${AWS_REGION:-us-west-2}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-906352610196}"
PROJECT_PREFIX="${PROJECT_PREFIX:-samosachaat}"
STATE_DIR="${STATE_DIR:-${ROOT_DIR}/.aws-cost}"
EC2_FALLBACK_INSTANCE_ID="${EC2_FALLBACK_INSTANCE_ID:-i-0ffd4a06829de2f1c}"

export AWS_PROFILE AWS_REGION

log() {
  printf '[samosaChaat cost] %s\n' "$*"
}

warn() {
  printf '[samosaChaat cost] WARN: %s\n' "$*" >&2
}

err() {
  printf '[samosaChaat cost] ERROR: %s\n' "$*" >&2
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Missing required command: $1"
    exit 127
  fi
}

check_prereqs() {
  need_cmd aws
  need_cmd jq
  need_cmd kubectl
  need_cmd helm
}

confirm_or_exit() {
  local yes="$1"
  local message="$2"
  if [[ "$yes" == "true" ]]; then
    return
  fi
  printf '%s [y/N] ' "$message"
  read -r reply
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    log "Aborted."
    exit 0
  fi
}

ensure_state_dir() {
  mkdir -p "$STATE_DIR/nodegroups"
}

discover_clusters() {
  aws eks list-clusters \
    --region "$AWS_REGION" \
    --query "clusters[?starts_with(@, '${PROJECT_PREFIX}-')]" \
    --output text | tr '\t' '\n' | sed '/^$/d' | sort
}

discover_nodegroups() {
  local cluster="$1"
  aws eks list-nodegroups \
    --region "$AWS_REGION" \
    --cluster-name "$cluster" \
    --query 'nodegroups[]' \
    --output text 2>/dev/null | tr '\t' '\n' | sed '/^$/d' | sort || true
}

nodegroup_state_file() {
  local cluster="$1"
  local nodegroup="$2"
  printf '%s/nodegroups/%s__%s.json' "$STATE_DIR" "$cluster" "$nodegroup"
}

save_nodegroup_scaling() {
  local cluster="$1"
  local nodegroup="$2"
  local file
  file="$(nodegroup_state_file "$cluster" "$nodegroup")"
  aws eks describe-nodegroup \
    --region "$AWS_REGION" \
    --cluster-name "$cluster" \
    --nodegroup-name "$nodegroup" \
    --query 'nodegroup.scalingConfig' \
    --output json > "$file"
}

restore_scaling_config() {
  local cluster="$1"
  local nodegroup="$2"
  local file min desired max
  file="$(nodegroup_state_file "$cluster" "$nodegroup")"
  if [[ -f "$file" ]]; then
    min="$(jq -r '.minSize // 2' "$file")"
    desired="$(jq -r '.desiredSize // 2' "$file")"
    max="$(jq -r '.maxSize // 4' "$file")"
  else
    min=2
    desired=2
    max=4
    warn "No saved scaling state for ${cluster}/${nodegroup}; using min=${min}, desired=${desired}, max=${max}."
  fi
  printf 'minSize=%s,desiredSize=%s,maxSize=%s' "$min" "$desired" "$max"
}

kubeconfig_for_cluster() {
  local cluster="$1"
  aws eks update-kubeconfig \
    --name "$cluster" \
    --region "$AWS_REGION" >/dev/null
}

samosachaat_namespaces() {
  kubectl get ns -o json 2>/dev/null \
    | jq -r '.items[].metadata.name | select(startswith("samosachaat-"))' \
    | sort || true
}

terraform_env_for_runtime() {
  local env="$1"
  if [[ "$env" =~ ^(dev|qa|uat)$ ]]; then
    printf 'dev'
  else
    printf '%s' "$env"
  fi
}

acm_cert_for_env() {
  local env="$1"
  local tf_env
  tf_env="$(terraform_env_for_runtime "$env")"
  terraform -chdir="${ROOT_DIR}/terraform/environments/${tf_env}" output -raw acm_certificate_arn 2>/dev/null || true
}

ecr_registry() {
  printf '%s.dkr.ecr.%s.amazonaws.com' "$AWS_ACCOUNT_ID" "$AWS_REGION"
}

app_values_file() {
  local env="$1"
  printf '%s/helm/samosachaat/values-%s.yaml' "$ROOT_DIR" "$env"
}

rds_instances() {
  aws rds describe-db-instances \
    --region "$AWS_REGION" \
    --query "DBInstances[?starts_with(DBInstanceIdentifier, '${PROJECT_PREFIX}-')].[DBInstanceIdentifier,DBInstanceStatus]" \
    --output text | sort
}

rds_instance_status() {
  local db="$1"
  aws rds describe-db-instances \
    --region "$AWS_REGION" \
    --db-instance-identifier "$db" \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text 2>/dev/null || true
}

wait_for_rds_status() {
  local db="$1"
  local wanted="$2"
  local max_attempts="${3:-120}"
  local status=""
  for _ in $(seq 1 "$max_attempts"); do
    status="$(rds_instance_status "$db")"
    if [[ "$status" == "$wanted" ]]; then
      return 0
    fi
    sleep 15
  done
  warn "Timed out waiting for ${db} to become ${wanted}; current status is ${status:-unknown}."
  return 1
}

fallback_instance_state() {
  aws ec2 describe-instances \
    --region "$AWS_REGION" \
    --instance-ids "$EC2_FALLBACK_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text 2>/dev/null || true
}

count_samosachaat_albs() {
  aws resourcegroupstaggingapi get-resources \
    --region "$AWS_REGION" \
    --resource-type-filters elasticloadbalancing:loadbalancer \
    --tag-filters "Key=ingress.k8s.aws/stack" \
    --query 'length(ResourceTagMappingList)' \
    --output text 2>/dev/null || printf '0'
}

count_eks_worker_instances() {
  local cluster="$1"
  aws ec2 describe-instances \
    --region "$AWS_REGION" \
    --filters "Name=tag:eks:cluster-name,Values=${cluster}" "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down" \
    --query 'length(Reservations[].Instances[])' \
    --output text 2>/dev/null || printf '0'
}

wait_for_eks_workers_gone() {
  local cluster="$1"
  local max_attempts="${2:-90}"
  local count=""
  for _ in $(seq 1 "$max_attempts"); do
    count="$(count_eks_worker_instances "$cluster")"
    if [[ "$count" == "0" ]]; then
      return 0
    fi
    sleep 20
  done
  warn "Timed out waiting for ${cluster} worker EC2 instances to terminate; ${count:-unknown} still visible."
  return 1
}
