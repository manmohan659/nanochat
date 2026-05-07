#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 6 ]; then
  echo "Usage: $0 <namespace> <db-host> <db-port> <master-user> <db-name> <app-user>" >&2
  exit 2
fi

namespace="$1"
db_host="$2"
db_port="$3"
master_user="$4"
db_name="$5"
app_user="$6"

: "${DB_MASTER_PASSWORD:?DB_MASTER_PASSWORD is required}"
: "${DB_APP_PASSWORD:?DB_APP_PASSWORD is required}"

run_id="$(date +%s)"
secret_name="db-bootstrap-${run_id}"
job_name="db-bootstrap-${run_id}"

cleanup() {
  kubectl -n "$namespace" delete job "$job_name" --ignore-not-found=true >/dev/null 2>&1 || true
  kubectl -n "$namespace" delete secret "$secret_name" --ignore-not-found=true >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl create secret generic "$secret_name" \
  -n "$namespace" \
  --from-literal=DB_MASTER_PASSWORD="$DB_MASTER_PASSWORD" \
  --from-literal=DB_APP_PASSWORD="$DB_APP_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

cat <<YAML | kubectl apply -f - >/dev/null
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job_name}
  namespace: ${namespace}
  labels:
    app.kubernetes.io/name: samosachaat-db-bootstrap
    app.kubernetes.io/part-of: samosachaat
spec:
  ttlSecondsAfterFinished: 120
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: psql
          image: postgres:16-alpine
          imagePullPolicy: IfNotPresent
          env:
            - name: DB_HOST
              value: "${db_host}"
            - name: DB_PORT
              value: "${db_port}"
            - name: DB_MASTER_USER
              value: "${master_user}"
            - name: DB_NAME
              value: "${db_name}"
            - name: DB_APP_USER
              value: "${app_user}"
            - name: PGPASSWORD
              valueFrom:
                secretKeyRef:
                  name: ${secret_name}
                  key: DB_MASTER_PASSWORD
            - name: DB_APP_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: ${secret_name}
                  key: DB_APP_PASSWORD
          command:
            - sh
            - -ec
            - |
              psql -v ON_ERROR_STOP=1 \\
                -h "\${DB_HOST}" \\
                -p "\${DB_PORT}" \\
                -U "\${DB_MASTER_USER}" \\
                -d postgres \\
                -v db_name="\${DB_NAME}" \\
                -v app_user="\${DB_APP_USER}" \\
                -v app_password="\${DB_APP_PASSWORD}" <<'SQL'
              SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'app_user', :'app_password')
              WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_user')\gexec
              SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'app_user', :'app_password')\gexec
              SELECT format('CREATE DATABASE %I OWNER %I', :'db_name', :'app_user')
              WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db_name')\gexec
              SELECT format('ALTER DATABASE %I OWNER TO %I', :'db_name', :'app_user')\gexec
              \\connect :db_name
              SELECT format('GRANT USAGE, CREATE ON SCHEMA public TO %I', :'app_user')\gexec
              SELECT format('ALTER SCHEMA public OWNER TO %I', :'app_user')\gexec
              SQL
              echo "Logical database bootstrap complete."
YAML

if ! kubectl -n "$namespace" wait --for=condition=complete "job/${job_name}" --timeout=180s; then
  kubectl -n "$namespace" logs "job/${job_name}" || true
  exit 1
fi
