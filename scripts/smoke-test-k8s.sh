#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 <namespace> [blue|green]" >&2
  exit 2
fi

namespace="$1"
slot="${2:-}"
suffix=""
if [ -n "$slot" ]; then
  suffix="-$slot"
fi

rollout_timeout="${ROLLOUT_TIMEOUT:-5m}"
curl_image="${CURL_IMAGE:-curlimages/curl:8.10.1}"
run_id="${GITHUB_RUN_ID:-$(date +%s)}"

services=(
  "frontend:3000:/api/health"
  "auth:8001:/auth/health"
  "chat-api:8002:/api/health"
  "inference:8003:/health"
)

echo "Waiting for samosaChaat deployments in namespace ${namespace}${slot:+ slot ${slot}}"
for item in "${services[@]}"; do
  IFS=: read -r svc _ _ <<<"$item"
  kubectl -n "$namespace" rollout status "deployment/${svc}${suffix}" --timeout="$rollout_timeout"
done

echo "Running in-cluster smoke checks"
for item in "${services[@]}"; do
  IFS=: read -r svc port path <<<"$item"
  pod="smoke-${svc//-/}-${run_id}-${RANDOM}"
  pod="${pod:0:63}"
  url="http://${svc}${suffix}.${namespace}.svc.cluster.local:${port}${path}"
  echo "Checking ${url}"
  kubectl -n "$namespace" run "$pod" \
    --rm -i --restart=Never \
    --image="$curl_image" \
    --command -- curl -fsS --retry 3 --retry-delay 2 --max-time 10 "$url" >/dev/null
done

echo "Smoke checks passed"
