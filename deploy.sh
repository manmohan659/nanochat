#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# samosaChaat Deploy Switch
#
# Usage:
#   ./deploy.sh ec2          Deploy monolith to EC2 via docker-compose
#   ./deploy.sh ec2-down     Stop services on EC2
#   ./deploy.sh eks          Provision EKS + deploy via Helm (demo/grading)
#   ./deploy.sh eks-down     Tear down EKS (save $$$)
#   ./deploy.sh status       Show what's currently running
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWS_PROFILE="${AWS_PROFILE:-accmanmohanusfca}"
AWS_ACCOUNT="${AWS_ACCOUNT_ID:-906352610196}"
AWS_REGION="${AWS_REGION:-us-west-2}"
ECR_REGISTRY="${ECR_REGISTRY:-${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com}"
EC2_HOST="${EC2_HOST:-16.148.217.62}"
EC2_USER="ubuntu"
EC2_KEY="${EC2_KEY:-$HOME/Documents/FinalSemester/DevOps/hellokitty.pem}"
DOMAIN="samosachaat.art"

export AWS_PROFILE AWS_REGION

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[samosaChaat]${NC} $1"; }
warn() { echo -e "${YELLOW}[samosaChaat]${NC} $1"; }
err()  { echo -e "${RED}[samosaChaat]${NC} $1" >&2; }

urlencode() {
    python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

#─── EC2 MONOLITH ─────────────────────────────────────────────────────────────

ec2_deploy() {
    log "Deploying to EC2 monolith at ${EC2_HOST}..."

    # 1. Login to ECR locally to get credentials
    log "Logging into ECR..."
    aws ecr get-login-password --region ${AWS_REGION} | \
        ssh -i "${EC2_KEY}" -o StrictHostKeyChecking=no ${EC2_USER}@${EC2_HOST} \
        "docker login --username AWS --password-stdin ${ECR_REGISTRY}" 2>/dev/null

    # 2. Sync repo to EC2
    log "Syncing code to EC2..."
    ssh -i "${EC2_KEY}" ${EC2_USER}@${EC2_HOST} bash -s << 'REMOTE_SCRIPT'
        set -e
        cd /home/ubuntu

        # Clone or update repo
        if [ -d samosachaat ]; then
            cd samosachaat
            git fetch origin master
            git reset --hard origin/master
        else
            git clone https://github.com/manmohan659/nanochat.git samosachaat
            cd samosachaat
        fi

        # Ensure .env exists
        if [ ! -f .env ]; then
            cp .env.example .env
            echo "⚠️  Created .env from template — edit it with real values!"
        fi
REMOTE_SCRIPT

    # 3. Copy .env from local if it exists
    if [ -f "${SCRIPT_DIR}/.env" ]; then
        log "Syncing .env to EC2..."
        scp -i "${EC2_KEY}" "${SCRIPT_DIR}/.env" ${EC2_USER}@${EC2_HOST}:/home/ubuntu/samosachaat/.env
    fi

    # 4. Pull images and start services
    log "Pulling images and starting services..."
    ssh -i "${EC2_KEY}" ${EC2_USER}@${EC2_HOST} bash -s << REMOTE_DEPLOY
        set -e
        cd /home/ubuntu/samosachaat

        # Set ECR registry in environment
        export ECR_REGISTRY=${ECR_REGISTRY}
        export IMAGE_TAG=dev-latest

        # Pull latest images
        docker compose -f docker-compose.yml -f docker-compose.prod.yml pull

        # Start everything
        docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

        # Run DB migrations
        echo "Running database migrations..."
        sleep 5  # wait for postgres to be ready
        docker compose exec -T chat-api alembic -c db/alembic.ini upgrade head 2>/dev/null || \
            echo "Migrations skipped (may need manual .env setup)"

        echo ""
        docker compose ps
REMOTE_DEPLOY

    # 5. Setup SSL if not already done
    log "Checking SSL..."
    ssh -i "${EC2_KEY}" ${EC2_USER}@${EC2_HOST} bash -s << 'SSL_CHECK'
        if [ ! -d /etc/letsencrypt/live/samosachaat.art ]; then
            echo "Setting up SSL with certbot..."
            sudo apt-get update -qq && sudo apt-get install -y -qq certbot > /dev/null 2>&1
            sudo certbot certonly --standalone --non-interactive \
                --agree-tos -m manmohan659@gmail.com \
                -d samosachaat.art -d www.samosachaat.art \
                --pre-hook "docker compose -f /home/ubuntu/samosachaat/docker-compose.yml -f /home/ubuntu/samosachaat/docker-compose.prod.yml stop nginx" \
                --post-hook "docker compose -f /home/ubuntu/samosachaat/docker-compose.yml -f /home/ubuntu/samosachaat/docker-compose.prod.yml start nginx"
        else
            echo "SSL already configured."
        fi
SSL_CHECK

    echo ""
    log "EC2 deploy complete!"
    log "  App:     https://${DOMAIN}"
    log "  Grafana: https://${DOMAIN}/grafana/"
    log "  EC2:     ${EC2_HOST}"
}

ec2_down() {
    log "Stopping services on EC2..."
    ssh -i "${EC2_KEY}" ${EC2_USER}@${EC2_HOST} \
        "cd /home/ubuntu/samosachaat && docker compose -f docker-compose.yml -f docker-compose.prod.yml down"
    log "EC2 services stopped."
}

#─── EKS CLUSTER ──────────────────────────────────────────────────────────────

eks_deploy() {
    local ENV="${1:-dev}"
    if [[ ! "${ENV}" =~ ^(dev|qa|uat|prod)$ ]]; then
        err "Unsupported EKS environment: ${ENV}. Use dev, qa, uat, or prod."
        exit 2
    fi
    local APP_NAMESPACE="samosachaat-${ENV}"
    local INFRA_ENV="${ENV}"
    local INFRA_TIER="prod"
    if [[ "${ENV}" =~ ^(dev|qa|uat)$ ]]; then
        INFRA_ENV="dev"
        INFRA_TIER="nonprod"
    fi
    log "Provisioning ${INFRA_TIER} EKS/RDS infrastructure for runtime env ${ENV}... This takes ~15-20 minutes."

    cd "${SCRIPT_DIR}/terraform/environments/${INFRA_ENV}"

    # Init & apply Terraform
    log "Running terraform init..."
    terraform init

    local TF_APPLY_ARGS=(-auto-approve)
    if [ "${INFRA_ENV}" != "dev" ]; then
        local GITHUB_ACTIONS_ROLE_ARN_VALUE="${GITHUB_ACTIONS_ROLE_ARN:-}"
        if [ -z "${GITHUB_ACTIONS_ROLE_ARN_VALUE}" ]; then
            GITHUB_ACTIONS_ROLE_ARN_VALUE="$(aws iam get-role \
                --role-name samosachaat-dev-github-actions \
                --query 'Role.Arn' \
                --output text 2>/dev/null || true)"
        fi
        if [ -n "${GITHUB_ACTIONS_ROLE_ARN_VALUE}" ] && [ "${GITHUB_ACTIONS_ROLE_ARN_VALUE}" != "None" ]; then
            TF_APPLY_ARGS+=("-var=github_actions_role_arn=${GITHUB_ACTIONS_ROLE_ARN_VALUE}")
        else
            warn "GitHub Actions role ARN not found; CI/CD will not be able to deploy to ${ENV} until github_actions_role_arn is applied."
        fi
    fi
    if [ "${ENV}" = "prod" ]; then
        local EXISTING_ALB_ARN="" EXISTING_ALB_DNS="" EXISTING_ALB_ZONE_ID=""
        EXISTING_ALB_ARN="$(aws resourcegroupstaggingapi get-resources \
            --region "${AWS_REGION}" \
            --resource-type-filters elasticloadbalancing:loadbalancer \
            --tag-filters "Key=ingress.k8s.aws/stack,Values=${APP_NAMESPACE}/samosachaat" \
            --query 'ResourceTagMappingList[0].ResourceARN' \
            --output text 2>/dev/null || true)"
        if [ -n "${EXISTING_ALB_ARN}" ] && [ "${EXISTING_ALB_ARN}" != "None" ]; then
            EXISTING_ALB_DNS="$(aws elbv2 describe-load-balancers \
                --region "${AWS_REGION}" \
                --load-balancer-arns "${EXISTING_ALB_ARN}" \
                --query 'LoadBalancers[0].DNSName' \
                --output text 2>/dev/null || true)"
            EXISTING_ALB_ZONE_ID="$(aws elbv2 describe-load-balancers \
                --region "${AWS_REGION}" \
                --load-balancer-arns "${EXISTING_ALB_ARN}" \
                --query 'LoadBalancers[0].CanonicalHostedZoneId' \
                --output text 2>/dev/null || true)"
            if [ -n "${EXISTING_ALB_DNS}" ] && [ "${EXISTING_ALB_DNS}" != "None" ] && \
               [ -n "${EXISTING_ALB_ZONE_ID}" ] && [ "${EXISTING_ALB_ZONE_ID}" != "None" ]; then
                TF_APPLY_ARGS+=("-var=alb_dns_name=${EXISTING_ALB_DNS}" "-var=alb_zone_id=${EXISTING_ALB_ZONE_ID}")
            fi
        fi
    fi

    log "Running terraform apply..."
    terraform apply "${TF_APPLY_ARGS[@]}"

    # Get cluster info
    local CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "samosachaat-${INFRA_ENV}-eks")
    local DB_ENDPOINT DB_HOST DB_PORT DB_MASTER_PASSWORD DB_MASTER_USER DB_APP_USER_VALUE DB_NAME DB_APP_PASSWORD_VALUE DATABASE_URL
    DB_ENDPOINT="$(terraform output -raw rds_endpoint)"
    DB_HOST="${DB_ENDPOINT%:*}"
    DB_PORT="${DB_ENDPOINT##*:}"
    DB_MASTER_PASSWORD="$(terraform output -raw rds_password)"
    DB_MASTER_USER="samosachaat_admin"
    DB_NAME="samosachaat_${ENV}"
    DB_APP_USER_VALUE="${DB_APP_USER:-samosachaat_${ENV}_app}"

    local JWT_DIR JWT_PRIVATE_KEY_FILE_RESOLVED JWT_PUBLIC_KEY_FILE_RESOLVED
    JWT_DIR="$(mktemp -d)"
    JWT_PRIVATE_KEY_FILE_RESOLVED="${JWT_PRIVATE_KEY_FILE:-}"
    JWT_PUBLIC_KEY_FILE_RESOLVED="${JWT_PUBLIC_KEY_FILE:-}"
    if [ -n "${JWT_PRIVATE_KEY:-}" ]; then
        JWT_PRIVATE_KEY_FILE_RESOLVED="${JWT_DIR}/jwt-private.pem"
        printf '%s' "${JWT_PRIVATE_KEY}" > "${JWT_PRIVATE_KEY_FILE_RESOLVED}"
    fi
    if [ -n "${JWT_PUBLIC_KEY:-}" ]; then
        JWT_PUBLIC_KEY_FILE_RESOLVED="${JWT_DIR}/jwt-public.pem"
        printf '%s' "${JWT_PUBLIC_KEY}" > "${JWT_PUBLIC_KEY_FILE_RESOLVED}"
    fi
    if [ -z "${JWT_PRIVATE_KEY_FILE_RESOLVED}" ] || [ -z "${JWT_PUBLIC_KEY_FILE_RESOLVED}" ]; then
        warn "JWT key files were not provided; generating demo keys for this deploy."
        JWT_PRIVATE_KEY_FILE_RESOLVED="${JWT_DIR}/jwt-private.pem"
        JWT_PUBLIC_KEY_FILE_RESOLVED="${JWT_DIR}/jwt-public.pem"
        openssl genrsa -out "${JWT_PRIVATE_KEY_FILE_RESOLVED}" 2048 >/dev/null 2>&1
        openssl rsa -in "${JWT_PRIVATE_KEY_FILE_RESOLVED}" -pubout -out "${JWT_PUBLIC_KEY_FILE_RESOLVED}" >/dev/null 2>&1
    fi

    local INTERNAL_API_KEY_VALUE SESSION_SECRET_VALUE
    INTERNAL_API_KEY_VALUE="${INTERNAL_API_KEY:-$(openssl rand -hex 32)}"
    SESSION_SECRET_VALUE="${SESSION_SECRET:-$(openssl rand -hex 32)}"

    log "Configuring kubectl for ${CLUSTER_NAME}..."
    aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region ${AWS_REGION}
    kubectl create namespace "${APP_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

    if [ -n "${DB_APP_PASSWORD:-}" ]; then
        DB_APP_PASSWORD_VALUE="${DB_APP_PASSWORD}"
    else
        local EXISTING_DATABASE_URL=""
        EXISTING_DATABASE_URL="$(kubectl get secret samosachaat-secrets \
            -n "${APP_NAMESPACE}" \
            -o jsonpath='{.data.DATABASE_URL}' 2>/dev/null | base64 -d 2>/dev/null || true)"
        if [ -n "${EXISTING_DATABASE_URL}" ]; then
            DB_APP_PASSWORD_VALUE="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(urllib.parse.urlsplit(sys.argv[1]).password or ""))' "${EXISTING_DATABASE_URL}")"
        fi
        if [ -z "${DB_APP_PASSWORD_VALUE:-}" ]; then
            DB_APP_PASSWORD_VALUE="$(openssl rand -base64 32 | tr -d '\n')"
        fi
    fi

    log "Ensuring logical database ${DB_NAME} exists on ${INFRA_TIER} RDS..."
    DB_MASTER_PASSWORD="${DB_MASTER_PASSWORD}" DB_APP_PASSWORD="${DB_APP_PASSWORD_VALUE}" \
        "${SCRIPT_DIR}/scripts/bootstrap-rds-logical-db.sh" \
        "${APP_NAMESPACE}" "${DB_HOST}" "${DB_PORT}" "${DB_MASTER_USER}" "${DB_NAME}" "${DB_APP_USER_VALUE}"

    DATABASE_URL="postgresql+asyncpg://$(urlencode "$DB_APP_USER_VALUE"):$(urlencode "$DB_APP_PASSWORD_VALUE")@${DB_HOST}:${DB_PORT}/${DB_NAME}"

    local K8S_APP_SECRET_ARGS=(
        --from-literal="DATABASE_URL=${DATABASE_URL}"
        --from-literal="DATABASE_NAME=${DB_NAME}"
        --from-literal="DATABASE_USER=${DB_APP_USER_VALUE}"
        --from-literal="RDS_ISOLATION_TIER=${INFRA_TIER}"
        --from-literal="AUTH_SERVICE_URL=http://auth:8001"
        --from-literal="CHAT_API_URL=http://chat-api:8002"
        --from-literal="INFERENCE_SERVICE_URL=${INFERENCE_SERVICE_URL:-http://inference:8003}"
        --from-literal="AUTH_BASE_URL=https://${DOMAIN}"
        --from-literal="FRONTEND_URL=https://${DOMAIN}"
        --from-literal="COOKIE_SECURE=true"
        --from-literal="COOKIE_DOMAIN=${DOMAIN}"
        --from-literal="INTERNAL_API_KEY=${INTERNAL_API_KEY_VALUE}"
        --from-literal="SESSION_SECRET=${SESSION_SECRET_VALUE}"
        --from-file="JWT_PRIVATE_KEY=${JWT_PRIVATE_KEY_FILE_RESOLVED}"
        --from-file="JWT_PUBLIC_KEY=${JWT_PUBLIC_KEY_FILE_RESOLVED}"
    )
    for secret_name in GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET GITHUB_CLIENT_ID GITHUB_CLIENT_SECRET HF_TOKEN; do
        secret_value="${!secret_name:-}"
        if [ -n "${secret_value}" ]; then
            K8S_APP_SECRET_ARGS+=(--from-literal="${secret_name}=${secret_value}")
        fi
    done

    kubectl create secret generic samosachaat-secrets \
        -n "${APP_NAMESPACE}" \
        "${K8S_APP_SECRET_ARGS[@]}" \
        --dry-run=client -o yaml | kubectl apply -f -

    if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
        kubectl create secret generic alertmanager-slack-webhook \
            -n "${APP_NAMESPACE}" \
            --from-literal=url="${SLACK_WEBHOOK_URL}" \
            --dry-run=client -o yaml | kubectl apply -f -
    else
        warn "SLACK_WEBHOOK_URL is not set; skipping observability install because Alertmanager needs a real Slack webhook for the final demo."
    fi

    local GRAFANA_OAUTH_READY="false"
    if [ -n "${GITHUB_GRAFANA_CLIENT_ID:-}" ] && [ -n "${GITHUB_GRAFANA_CLIENT_SECRET:-}" ] && \
       [ -n "${GOOGLE_GRAFANA_CLIENT_ID:-}" ] && [ -n "${GOOGLE_GRAFANA_CLIENT_SECRET:-}" ]; then
        GRAFANA_OAUTH_READY="true"
        kubectl create secret generic grafana-oauth-secrets \
            -n "${APP_NAMESPACE}" \
            --from-literal=GITHUB_GRAFANA_CLIENT_ID="${GITHUB_GRAFANA_CLIENT_ID}" \
            --from-literal=GITHUB_GRAFANA_CLIENT_SECRET="${GITHUB_GRAFANA_CLIENT_SECRET}" \
            --from-literal=GOOGLE_GRAFANA_CLIENT_ID="${GOOGLE_GRAFANA_CLIENT_ID}" \
            --from-literal=GOOGLE_GRAFANA_CLIENT_SECRET="${GOOGLE_GRAFANA_CLIENT_SECRET}" \
            --from-literal=SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}" \
            --dry-run=client -o yaml | kubectl apply -f -
    else
        warn "Grafana OAuth env vars are incomplete; skipping observability install until real OAuth secrets are present."
    fi

    # Install ALB Ingress Controller
    if kubectl -n kube-system rollout status deployment/aws-load-balancer-controller --timeout=30s >/dev/null 2>&1; then
        log "ALB Ingress Controller is already healthy; skipping controller upgrade."
    else
        log "Installing ALB Ingress Controller..."
        helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
        helm repo update
        helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
            -n kube-system \
            --set clusterName="${CLUSTER_NAME}" \
            --set serviceAccount.create=true \
            --set serviceAccount.name=aws-load-balancer-controller \
            --set "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=$(terraform output -raw alb_controller_role_arn)" \
            --wait --timeout 5m 2>/dev/null || warn "ALB controller may need IRSA setup"
    fi

    # Deploy observability stack
    if [ -n "${SLACK_WEBHOOK_URL:-}" ] && [ "${GRAFANA_OAUTH_READY}" = "true" ]; then
        log "Deploying observability stack..."
        helm dependency build "${SCRIPT_DIR}/helm/observability" 2>/dev/null || true
        helm upgrade --install observability "${SCRIPT_DIR}/helm/observability" \
            --namespace "${APP_NAMESPACE}" --create-namespace \
            --wait --timeout 10m
    else
        warn "Observability stack was not installed. Set SLACK_WEBHOOK_URL plus Grafana GitHub/Google OAuth vars, then rerun ./deploy.sh eks ${ENV}."
    fi

    # Deploy samosaChaat
    local VALUES_FILE="${SCRIPT_DIR}/helm/samosachaat/values-${ENV}.yaml"
    log "Deploying samosaChaat to EKS..."
    if [ "${ENV}" = "prod" ]; then
        helm upgrade --install samosachaat-traffic "${SCRIPT_DIR}/helm/samosachaat" \
            -f "${VALUES_FILE}" \
            --set frontend.enabled=false \
            --set auth.enabled=false \
            --set chatApi.enabled=false \
            --set inference.enabled=false \
            --set dbMigrate.enabled=false \
            --set ingress.enabled=false \
            --set ingress.targetSlot=blue \
            --set secrets.create=false \
            --namespace "${APP_NAMESPACE}" --create-namespace \
            --wait --timeout 10m
        helm upgrade --install samosachaat-blue "${SCRIPT_DIR}/helm/samosachaat" \
            -f "${VALUES_FILE}" \
            --set global.imageRegistry="${ECR_REGISTRY}" \
            --set global.imageTag="dev-latest" \
            --set deployment.slot=blue \
            --set ingress.enabled=false \
            --set namespace.create=false \
            --set configMap.create=false \
            --set secrets.create=false \
            --namespace "${APP_NAMESPACE}" --create-namespace \
            --wait --timeout 15m
        helm upgrade samosachaat-traffic "${SCRIPT_DIR}/helm/samosachaat" \
            --reuse-values \
            --set ingress.enabled=true \
            --set ingress.targetSlot=blue \
            --set ingress.acmCertArn="$(terraform output -raw acm_certificate_arn 2>/dev/null || echo '')" \
            --namespace "${APP_NAMESPACE}" \
            --wait --timeout 10m
    else
        helm upgrade --install samosachaat "${SCRIPT_DIR}/helm/samosachaat" \
            -f "${VALUES_FILE}" \
            --set global.imageRegistry="${ECR_REGISTRY}" \
            --set global.imageTag="dev-latest" \
            --set ingress.acmCertArn="$(terraform output -raw acm_certificate_arn 2>/dev/null || echo '')" \
            --set secrets.create=false \
            --namespace "${APP_NAMESPACE}" --create-namespace \
            --wait --timeout 10m
    fi

    if [ "${ENV}" = "prod" ]; then
        log "Resolving prod ALB address and reconciling Route53 aliases with Terraform..."
        local ALB_HOST="" ALB_LOOKUP="" ALB_ZONE_ID=""
        for _ in {1..40}; do
            ALB_HOST="$(kubectl get ingress samosachaat -n "${APP_NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
            if [ -n "${ALB_HOST}" ]; then
                break
            fi
            sleep 15
        done
        if [ -z "${ALB_HOST}" ]; then
            local ALB_ARN=""
            ALB_ARN="$(aws resourcegroupstaggingapi get-resources \
                --region "${AWS_REGION}" \
                --resource-type-filters elasticloadbalancing:loadbalancer \
                --tag-filters "Key=ingress.k8s.aws/stack,Values=${APP_NAMESPACE}/samosachaat" \
                --query 'ResourceTagMappingList[0].ResourceARN' \
                --output text 2>/dev/null || true)"
            if [ -n "${ALB_ARN}" ] && [ "${ALB_ARN}" != "None" ]; then
                ALB_HOST="$(aws elbv2 describe-load-balancers \
                    --region "${AWS_REGION}" \
                    --load-balancer-arns "${ALB_ARN}" \
                    --query 'LoadBalancers[0].DNSName' \
                    --output text 2>/dev/null || true)"
            fi
        fi
        if [ -n "${ALB_HOST}" ]; then
            ALB_LOOKUP="${ALB_HOST#dualstack.}"
            ALB_ZONE_ID="$(aws elbv2 describe-load-balancers \
                --region "${AWS_REGION}" \
                --query "LoadBalancers[?DNSName=='${ALB_LOOKUP}'].CanonicalHostedZoneId | [0]" \
                --output text 2>/dev/null || true)"
            if [ -n "${ALB_ZONE_ID}" ] && [ "${ALB_ZONE_ID}" != "None" ]; then
                terraform apply "${TF_APPLY_ARGS[@]}" \
                    -var="alb_dns_name=${ALB_LOOKUP}" \
                    -var="alb_zone_id=${ALB_ZONE_ID}"
            else
                warn "Could not resolve ALB hosted-zone ID for ${ALB_LOOKUP}; Route53 alias was not updated."
            fi
        else
            warn "Ingress did not publish an ALB hostname yet; Route53 alias was not updated."
        fi
    else
        warn "Skipping Route53 alias reconciliation for ${ENV}; only prod is allowed to move samosachaat.art away from the EC2 fallback."
    fi

    echo ""
    log "EKS deploy complete!"
    log "  Cluster: ${CLUSTER_NAME}"
    kubectl get pods -n "${APP_NAMESPACE}"
    echo ""
    kubectl get ingress -n "${APP_NAMESPACE}" 2>/dev/null || true
}

eks_down() {
    local ENV="${1:-dev}"
    if [[ "${ENV}" =~ ^(qa|uat)$ ]]; then
        local CLUSTER_NAME
        CLUSTER_NAME="$(terraform -chdir="${SCRIPT_DIR}/terraform/environments/dev" output -raw cluster_name 2>/dev/null || echo "samosachaat-dev-eks")"
        local APP_NAMESPACE="samosachaat-${ENV}"
        warn "Removing only namespace-scoped ${ENV} releases from the shared non-prod cluster. This will not destroy shared EKS/RDS infrastructure."
        aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region ${AWS_REGION} 2>/dev/null || true
        helm uninstall samosachaat -n "${APP_NAMESPACE}" 2>/dev/null || true
        helm uninstall observability -n "${APP_NAMESPACE}" 2>/dev/null || true
        kubectl delete namespace "${APP_NAMESPACE}" --ignore-not-found=true
        return
    fi
    warn "Tearing down EKS cluster (${ENV})... This saves ~\$0.10/hr + node costs."

    cd "${SCRIPT_DIR}/terraform/environments/${ENV}"

    # Remove Helm releases first (cleans up ALB, etc.)
    local CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "samosachaat-${ENV}-eks")
    local APP_NAMESPACE="samosachaat-${ENV}"
    aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region ${AWS_REGION} 2>/dev/null || true

    log "Removing Helm releases..."
    helm uninstall samosachaat -n "${APP_NAMESPACE}" 2>/dev/null || true
    helm uninstall samosachaat-traffic -n "${APP_NAMESPACE}" 2>/dev/null || true
    helm uninstall samosachaat-blue -n "${APP_NAMESPACE}" 2>/dev/null || true
    helm uninstall samosachaat-green -n "${APP_NAMESPACE}" 2>/dev/null || true
    helm uninstall observability -n "${APP_NAMESPACE}" 2>/dev/null || true
    helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true

    # Destroy infrastructure
    log "Running terraform destroy..."
    terraform destroy -auto-approve

    log "EKS cluster destroyed. Costs stopped."
}

#─── STATUS ───────────────────────────────────────────────────────────────────

show_status() {
    echo ""
    log "=== samosaChaat Deployment Status ==="
    echo ""

    # Check EC2
    echo "EC2 Monolith (${EC2_HOST}):"
    if ssh -i "${EC2_KEY}" -o ConnectTimeout=5 ${EC2_USER}@${EC2_HOST} \
        "docker compose -f /home/ubuntu/samosachaat/docker-compose.yml -f /home/ubuntu/samosachaat/docker-compose.prod.yml ps --format 'table {{.Name}}\t{{.Status}}'" 2>/dev/null; then
        echo ""
    else
        echo "  Not running or unreachable."
    fi

    # Check EKS
    echo "EKS Cluster:"
    if kubectl get nodes 2>/dev/null; then
        echo ""
        for ns in samosachaat-dev samosachaat-qa samosachaat-uat samosachaat-prod; do
            kubectl get pods -n "$ns" 2>/dev/null || true
        done
    else
        echo "  No EKS cluster configured."
    fi

    # Check ECR images
    echo ""
    echo "ECR Images (latest):"
    for svc in frontend auth chat-api inference; do
        TAG=$(aws ecr describe-images --repository-name samosachaat/${svc} --region ${AWS_REGION} \
            --query 'sort_by(imageDetails,&imagePushedAt)[-1].imageTags[0]' --output text 2>/dev/null || echo "none")
        echo "  samosachaat/${svc}: ${TAG}"
    done
}

#─── MAIN ─────────────────────────────────────────────────────────────────────

case "${1:-help}" in
    ec2)        ec2_deploy ;;
    ec2-down)   ec2_down ;;
    eks)        eks_deploy "${2:-dev}" ;;
    eks-down)   eks_down "${2:-dev}" ;;
    status)     show_status ;;
    *)
        echo "samosaChaat Deploy Switch"
        echo ""
        echo "Usage: ./deploy.sh <mode>"
        echo ""
        echo "Modes:"
        echo "  ec2          Deploy monolith to EC2 (cheap, always-on)"
        echo "  ec2-down     Stop EC2 services"
        echo "  eks [env]    Provision EKS + deploy (demo/grading) [dev|qa|uat|prod]"
        echo "  eks-down     Tear down EKS or remove a shared non-prod namespace"
        echo "  status       Show what's running"
        ;;
esac
