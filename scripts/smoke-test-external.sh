#!/usr/bin/env bash
set -euo pipefail

# Verify public DNS, TLS, and ALB routing for an environment.
# Usage: ./scripts/smoke-test-external.sh <dev|qa|uat|prod>

ENVIRONMENT="${1:?Usage: smoke-test-external.sh <dev|qa|uat|prod>}"
case "$ENVIRONMENT" in
  dev|qa|uat) HOST="${ENVIRONMENT}.samosachaat.art" ;;
  prod) HOST="samosachaat.art" ;;
  *) echo "Unsupported environment: $ENVIRONMENT" >&2; exit 2 ;;
esac

check_url() {
  local url="$1"
  echo "Checking $url"
  curl -fsSL --retry 12 --retry-delay 10 --max-time 15 -o /dev/null "$url"
}

check_url "https://${HOST}/"
check_url "https://${HOST}/api/health"
check_url "https://${HOST}/auth/health"

if [[ "$ENVIRONMENT" == "prod" ]]; then
  check_url "https://grafana.samosachaat.art/api/health"
fi

echo "External DNS/TLS smoke checks passed for $ENVIRONMENT"
