#!/usr/bin/env bash
set -euo pipefail

# Bootstrap the per-environment logical database and sync Kubernetes runtime
# secrets from Terraform outputs plus CI-provided application secrets.
#
# Usage: ./scripts/sync-runtime-env.sh <dev|qa|uat|prod>

ENVIRONMENT="${1:?Usage: sync-runtime-env.sh <dev|qa|uat|prod>}"
if [[ ! "$ENVIRONMENT" =~ ^(dev|qa|uat|prod)$ ]]; then
  echo "Unsupported environment: $ENVIRONMENT" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
NAMESPACE="samosachaat-${ENVIRONMENT}"
INFRA_ENV="$ENVIRONMENT"
RDS_ISOLATION_TIER="prod"
PUBLIC_HOST="samosachaat.art"

if [[ "$ENVIRONMENT" =~ ^(dev|qa|uat)$ ]]; then
  INFRA_ENV="dev"
  RDS_ISOLATION_TIER="nonprod"
  PUBLIC_HOST="${ENVIRONMENT}.samosachaat.art"
fi

TF_DIR="${ROOT_DIR}/terraform/environments/${INFRA_ENV}"
DB_MASTER_USER="${DB_MASTER_USER:-samosachaat_admin}"
DB_NAME="${DB_NAME:-samosachaat_${ENVIRONMENT}}"
DB_APP_USER="${DB_APP_USER:-samosachaat_${ENVIRONMENT}_app}"

required=(
  INTERNAL_API_KEY
  SESSION_SECRET
  JWT_PRIVATE_KEY
  JWT_PUBLIC_KEY
  GOOGLE_CLIENT_ID
  GOOGLE_CLIENT_SECRET
  GITHUB_CLIENT_ID
  GITHUB_CLIENT_SECRET
)

if [[ "$ENVIRONMENT" == "prod" ]]; then
  required+=(GITHUB_GRAFANA_CLIENT_ID GITHUB_GRAFANA_CLIENT_SECRET SLACK_WEBHOOK_URL)
fi

for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required runtime secret: $name" >&2
    exit 1
  fi
done

urlencode() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

terraform -chdir="$TF_DIR" init -input=false >/dev/null

DB_ENDPOINT="$(terraform -chdir="$TF_DIR" output -raw rds_endpoint)"
DB_HOST="${DB_ENDPOINT%:*}"
DB_PORT="${DB_ENDPOINT##*:}"
DB_MASTER_PASSWORD="$(terraform -chdir="$TF_DIR" output -raw rds_password)"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

if [[ -z "${DB_APP_PASSWORD:-}" ]]; then
  existing_url="$(
    kubectl get secret samosachaat-secrets \
      -n "$NAMESPACE" \
      -o jsonpath='{.data.DATABASE_URL}' 2>/dev/null | base64 -d 2>/dev/null || true
  )"
  if [[ -n "$existing_url" ]]; then
    DB_APP_PASSWORD="$(
      python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(urllib.parse.urlsplit(sys.argv[1]).password or ""))' "$existing_url"
    )"
  fi
fi
if [[ -z "${DB_APP_PASSWORD:-}" ]]; then
  DB_APP_PASSWORD="$(openssl rand -base64 32 | tr -d '\n')"
fi

echo "Ensuring $DB_NAME and $DB_APP_USER exist on $RDS_ISOLATION_TIER RDS"
DB_MASTER_PASSWORD="$DB_MASTER_PASSWORD" DB_APP_PASSWORD="$DB_APP_PASSWORD" \
  "${SCRIPT_DIR}/bootstrap-rds-logical-db.sh" \
  "$NAMESPACE" "$DB_HOST" "$DB_PORT" "$DB_MASTER_USER" "$DB_NAME" "$DB_APP_USER"

DATABASE_URL="postgresql+asyncpg://$(urlencode "$DB_APP_USER"):$(urlencode "$DB_APP_PASSWORD")@${DB_HOST}:${DB_PORT}/${DB_NAME}"

jwt_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$jwt_dir"
}
trap cleanup EXIT
printf '%s' "$JWT_PRIVATE_KEY" > "${jwt_dir}/jwt-private.pem"
printf '%s' "$JWT_PUBLIC_KEY" > "${jwt_dir}/jwt-public.pem"

secret_args=(
  --from-literal="DATABASE_URL=${DATABASE_URL}"
  --from-literal="DATABASE_NAME=${DB_NAME}"
  --from-literal="DATABASE_USER=${DB_APP_USER}"
  --from-literal="RDS_ISOLATION_TIER=${RDS_ISOLATION_TIER}"
  --from-literal="AUTH_SERVICE_URL=http://auth:8001"
  --from-literal="CHAT_API_URL=http://chat-api:8002"
  --from-literal="INFERENCE_SERVICE_URL=${INFERENCE_SERVICE_URL:-http://inference:8003}"
  --from-literal="AUTH_BASE_URL=https://${PUBLIC_HOST}"
  --from-literal="FRONTEND_URL=https://${PUBLIC_HOST}"
  --from-literal="COOKIE_SECURE=true"
  --from-literal="COOKIE_DOMAIN=.samosachaat.art"
  --from-literal="INTERNAL_API_KEY=${INTERNAL_API_KEY}"
  --from-literal="SESSION_SECRET=${SESSION_SECRET}"
  --from-literal="GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID}"
  --from-literal="GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET}"
  --from-literal="GITHUB_CLIENT_ID=${GITHUB_CLIENT_ID}"
  --from-literal="GITHUB_CLIENT_SECRET=${GITHUB_CLIENT_SECRET}"
  --from-literal="HF_TOKEN=${HF_TOKEN:-}"
  --from-file="JWT_PRIVATE_KEY=${jwt_dir}/jwt-private.pem"
  --from-file="JWT_PUBLIC_KEY=${jwt_dir}/jwt-public.pem"
)

kubectl create secret generic samosachaat-secrets \
  -n "$NAMESPACE" \
  "${secret_args[@]}" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

if [[ "$ENVIRONMENT" == "prod" ]]; then
  kubectl create secret generic alertmanager-slack-webhook \
    -n "$NAMESPACE" \
    --from-literal=url="${SLACK_WEBHOOK_URL}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null

  kubectl create secret generic grafana-oauth-secrets \
    -n "$NAMESPACE" \
    --from-literal=GITHUB_GRAFANA_CLIENT_ID="${GITHUB_GRAFANA_CLIENT_ID}" \
    --from-literal=GITHUB_GRAFANA_CLIENT_SECRET="${GITHUB_GRAFANA_CLIENT_SECRET}" \
    --from-literal=SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
fi

echo "Runtime environment synced for ${ENVIRONMENT} in namespace ${NAMESPACE}"
