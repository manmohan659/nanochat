# SamosaChaat Railway Deployment

This is the active low-budget deployment path for SamosaChaat. The AWS/EKS
DevOps work remains in `terraform/`, `helm/`, `.github/workflows/`, `docs/`,
and `scripts/` as portfolio evidence. Do not run `terraform apply` for this
Railway deployment.

## Decision

Use the same repository and a Railway-specific branch/worktree. Do not create a
separate lightweight repo. The service code already maps cleanly to Railway
services, and keeping the monorepo preserves the AWS/EKS evidence.

Chosen low-cost shape:

| Railway service | Source | Public? | Notes |
| --- | --- | --- | --- |
| `Postgres` | Railway PostgreSQL | No public app URL | Provides `DATABASE_URL` to auth and chat-api. |
| `frontend` | `services/frontend` | Yes | Next.js web app and BFF routes. |
| `auth` | `services/auth` | Yes | Public URL is required for OAuth callbacks. |
| `chat-api` | repo root with `services/chat-api/Dockerfile` | No | Private API for frontend; runs Alembic pre-deploy migrations. |
| `inference` | `services/inference` | No | Run in low-cost fallback/proxy mode by default. |

Do not deploy Grafana, Prometheus, Loki, Promtail, Alertmanager, EKS, RDS, ECR,
Route53, or ACM on Railway. Those remain part of the retained AWS architecture,
not the budget deployment.

## Why This Shape

The full AWS version used five runtime components plus observability. Railway can
host the four app services directly, but always-on services can cost more than a
small budget expects. Use one replica per app service, Railway private
networking, serverless sleep on app services, and a hard workspace usage limit.

The expensive/risky part is local model serving. The Railway inference service
should start with:

```text
STARTUP_LOAD_ENABLED=false
DEMO_FALLBACK_ENABLED=true
```

That avoids downloading/loading model weights on Railway CPU. If a Modal or
other external generation endpoint is available, set `UPSTREAM_GENERATE_URL`.
If not, inference returns a demo fallback response so the deployed app remains
usable for a low-cost portfolio demo.

## Railway Docs Checked

- [Dockerfiles](https://docs.railway.com/builds/dockerfiles): Dockerfile
  services can use `RAILWAY_DOCKERFILE_PATH` or config-as-code
  `dockerfilePath` for non-root Dockerfiles.
- [Healthchecks](https://docs.railway.com/deployments/healthchecks): services
  must listen on the `PORT` Railway provides or the manually configured service
  `PORT`; Railway waits for a `200` health response before promoting a deploy.
- [Private networking](https://docs.railway.com/private-networking): internal
  service calls use `SERVICE_NAME.railway.internal` plus the port the target
  service listens on.
- [PostgreSQL](https://docs.railway.com/databases/postgresql): Railway Postgres
  exposes `DATABASE_URL`.
- [Cost control](https://docs.railway.com/pricing/cost-control) and
  [Serverless](https://docs.railway.com/deployments/serverless): cost controls
  include usage limits, replica limits, private networking, and serverless
  sleep.

## Service Settings

Create a Railway project named `SamosaChaat` and add these services:

| Service | Root Directory | Config file path | Health check |
| --- | --- | --- | --- |
| `frontend` | `/services/frontend` | `/services/frontend/railway.toml` | `/api/health` |
| `auth` | `/services/auth` | `/services/auth/railway.toml` | `/auth/health` |
| `chat-api` | `/` | `/services/chat-api/railway.toml` | `/api/health` |
| `inference` | `/services/inference` | `/services/inference/railway.toml` | `/health` |

`chat-api` uses the repo root because its Dockerfile copies both
`services/chat-api` and `db/` for Alembic migrations.

Set these app-service `PORT` variables manually so private URLs are stable:

```text
frontend PORT=3000
auth PORT=8001
chat-api PORT=8002
inference PORT=8003
```

Generate Railway public domains only for `frontend` and `auth`. Keep `chat-api`
and `inference` private unless temporarily exposing them for debugging.

## Environment Variables

Use `railway/env.example` as the template. Do not paste real secrets into git.

Important service wiring:

```text
frontend:
  AUTH_PUBLIC_URL=https://${{auth.RAILWAY_PUBLIC_DOMAIN}}
  AUTH_SERVICE_URL=http://auth.railway.internal:8001
  CHAT_API_URL=http://chat-api.railway.internal:8002

auth:
  DATABASE_URL=${{Postgres.DATABASE_URL}}
  AUTH_BASE_URL=https://${{auth.RAILWAY_PUBLIC_DOMAIN}}
  FRONTEND_URL=https://${{frontend.RAILWAY_PUBLIC_DOMAIN}}
  COOKIE_SECURE=true
  COOKIE_DOMAIN=

chat-api:
  DATABASE_URL=${{Postgres.DATABASE_URL}}
  AUTH_SERVICE_URL=http://auth.railway.internal:8001
  INFERENCE_SERVICE_URL=http://inference.railway.internal:8003
  FRONTEND_URL=https://${{frontend.RAILWAY_PUBLIC_DOMAIN}}

inference:
  STARTUP_LOAD_ENABLED=false
  DEMO_FALLBACK_ENABLED=true
```

OAuth callback URLs:

```text
Google: https://<auth-public-domain>/auth/google/callback
GitHub: https://<auth-public-domain>/auth/github/callback
```

`JWT_PRIVATE_KEY` and `JWT_PUBLIC_KEY` must be an RS256 keypair. The repo
already has `scripts/generate-jwt-keys.sh` for local generation. Paste the PEM
values into Railway variables, not into tracked files.

## Deployment Order

1. Add Railway Postgres.
2. Add `auth`, configure variables, generate its public domain, deploy.
3. Add `inference`, configure low-cost fallback variables, deploy.
4. Add `chat-api`, configure variables, deploy. Its pre-deploy command runs:

```bash
alembic -c db/alembic.ini upgrade head
```

5. Add `frontend`, configure variables with the final auth/frontend domains,
   deploy.
6. Configure OAuth provider callback URLs after the `auth` public domain exists.
7. Redeploy `auth` and `frontend` after any domain or OAuth variable changes.

If using the Railway CLI after it is installed and authenticated:

```bash
railway link
railway up --service frontend --path services/frontend --path-as-root
railway up --service auth --path services/auth --path-as-root
railway up --service inference --path services/inference --path-as-root
railway up --service chat-api
```

For `chat-api`, deploy from the repo root so `db/` is available to the image.

## Database Migrations And Seed Data

Migrations are Alembic files in `db/migrations`. The `chat-api` Railway config
runs them before each deploy. This replaces the Helm pre-upgrade migration Job
from EKS.

Do not use `scripts/seed-db.sh` against Railway as-is; it targets local Docker
Compose Postgres. For Railway, prefer OAuth-created users and real app data. If
demo seed data is needed later, add a Railway-specific seed script that connects
through `DATABASE_URL` without Docker Compose.

## Verification

Public checks:

```bash
curl https://<frontend-public-domain>/api/health
curl https://<auth-public-domain>/auth/health
```

Expected frontend payload includes:

```json
{"status":"ok","service":"samosachaat-frontend"}
```

Expected auth payload:

```json
{"status":"ok"}
```

For private services, rely on Railway health checks or temporarily generate a
domain for debugging and remove it afterward:

```bash
curl https://<chat-api-debug-domain>/api/health
curl https://<inference-debug-domain>/health
```

Then test the browser flow:

1. Open the frontend public URL.
2. Click Google or GitHub login.
3. Confirm the auth service redirects back to `/chat?access_token=...`.
4. Create a conversation and send a message.
5. Confirm the response streams. In low-cost mode the response may be the demo
   fallback unless `UPSTREAM_GENERATE_URL` points to a real generation endpoint.

## Cost Controls

- Set a Railway compute hard limit in Workspace Usage before deploying.
- Enable Serverless for `frontend`, `auth`, `chat-api`, and `inference`.
- Use one replica per app service.
- Set conservative replica limits; raise only if deploys crash.
- Keep `chat-api` and `inference` private to avoid public egress and attack
  surface.
- Use `${{Postgres.DATABASE_URL}}`, not `DATABASE_PUBLIC_URL`.
- Do not deploy the observability stack on Railway for the budget version.
- Keep `STARTUP_LOAD_ENABLED=false` until you intentionally budget for model
  loading and storage.

## Known Limitations Compared With AWS/EKS

- No EKS node groups, Kubernetes scheduling, HPA, PDBs, or node rotation.
- No Route53/ACM-managed custom domain unless configured separately in Railway.
- No ALB blue/green slot switch. Railway deploys can overlap, but they are not
  the same Helm-driven blue/green architecture.
- No self-hosted Grafana, Prometheus, Loki, Promtail, or Alertmanager in the
  budget deployment.
- No EFS-backed model weights. Railway inference starts in fallback/proxy mode.
- Serverless sleep can cause cold starts and first-request delays.
- Private Railway service URLs are not accessible from browser client code; only
  server-side frontend routes should call them.

## Fallback If Four App Services Are Too Expensive

The cheapest interactive portfolio demo is `frontend` only, with no
`CHAT_API_URL`. The frontend then streams mock responses. That does not provide
OAuth persistence or database-backed conversations, so it should be labeled as a
frontend demo, not the full SamosaChaat app.

The cheapest practical full-app version is the chosen shape above: Postgres,
frontend, auth, chat-api, and inference fallback/proxy mode.
