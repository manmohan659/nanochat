# samosaChaat Platform — Production Architecture & Execution Plan

> **Goal**: Transform the nanochat single-server chat app into a production-grade, commercially viable AI chat platform with microservices architecture, deployed on AWS EKS via Terraform, with full CI/CD, observability, and zero-downtime deployments.
>
> **Domain**: `samosachaat.art`
>
> **Design Inspiration**: Sarvam.ai (clean sidebar, OAuth login, warm desi aesthetic) — but retaining samosaChaat's signature gold/cream/chutney-green palette, Baloo 2 font, samosa illustrations, and lemon-mirchi toran.

---

## Table of Contents

1. [Repository Structure](#1-repository-structure)
2. [Application Architecture Overview](#2-application-architecture-overview)
3. [Workstream A — Frontend Service](#workstream-a--frontend-service)
4. [Workstream B — Auth Service](#workstream-b--auth-service)
5. [Workstream C — Chat API Service](#workstream-c--chat-api-service)
6. [Workstream D — Inference Service](#workstream-d--inference-service)
7. [Workstream E — Database & Schema Management](#workstream-e--database--schema-management)
8. [Workstream F — Terraform / Infrastructure](#workstream-f--terraform--infrastructure)
9. [Workstream G — CI/CD Pipeline](#workstream-g--cicd-pipeline)
10. [Workstream H — Observability & Logging](#workstream-h--observability--logging)
11. [Workstream I — Day 2 Operations](#workstream-i--day-2-operations)
12. [Integration Contract & API Specs](#integration-contract--api-specs)
13. [Execution Order & Dependency Graph](#execution-order--dependency-graph)

---

## 1. Repository Structure

**Decision: Monorepo** — One repo, multiple services. Rationale:
- Shared API contracts (protobuf/OpenAPI specs) stay in sync
- Single CI pipeline with path-based triggers
- Atomic commits across services when contracts change
- Easier for EKS Helm chart coordination
- `samosachaat.art` is one product, not a platform of independent products

```
samosachaat/                          # Root (new repo OR restructured from nanochat)
├── .github/
│   └── workflows/
│       ├── ci.yml                    # Lint + test all services (path-filtered)
│       ├── build-dev.yml             # Build & push Docker images to ECR (dev tag)
│       ├── promote-uat.yml           # Triggered by RC tags → deploy to UAT
│       ├── release-prod.yml          # Triggered by v* tags → deploy to Prod
│       └── nightly.yml               # Nightly integration tests → QA
├── terraform/
│   ├── environments/
│   │   ├── dev/
│   │   ├── uat/
│   │   └── prod/
│   ├── modules/
│   │   ├── vpc/
│   │   ├── eks/
│   │   ├── rds/
│   │   ├── ecr/
│   │   ├── iam/
│   │   ├── route53/
│   │   └── acm/                      # SSL certificates
│   ├── backend.tf                    # S3 + DynamoDB state backend
│   └── versions.tf
├── helm/
│   ├── samosachaat/                   # Umbrella Helm chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml               # Base values
│   │   ├── values-dev.yaml
│   │   ├── values-uat.yaml
│   │   ├── values-prod.yaml
│   │   └── templates/
│   │       ├── frontend-deployment.yaml
│   │       ├── auth-deployment.yaml
│   │       ├── chat-api-deployment.yaml
│   │       ├── inference-deployment.yaml
│   │       ├── ingress.yaml           # ALB Ingress with SSL
│   │       ├── hpa.yaml               # Horizontal Pod Autoscaler
│   │       └── configmaps.yaml
│   └── observability/                 # Prometheus/Grafana/Loki stack
│       ├── Chart.yaml
│       └── values.yaml
├── services/
│   ├── frontend/                      # React/Next.js app
│   │   ├── Dockerfile
│   │   ├── package.json
│   │   ├── next.config.js
│   │   ├── public/
│   │   │   ├── samosa.svg
│   │   │   ├── chai.svg
│   │   │   └── logo.svg
│   │   └── src/
│   │       ├── app/
│   │       │   ├── layout.tsx
│   │       │   ├── page.tsx           # Landing page (hero)
│   │       │   ├── login/page.tsx     # OAuth login
│   │       │   └── chat/
│   │       │       ├── page.tsx       # Chat interface
│   │       │       └── [id]/page.tsx  # Specific conversation
│   │       ├── components/
│   │       │   ├── Navbar.tsx
│   │       │   ├── Sidebar.tsx        # Chat history list
│   │       │   ├── ChatInput.tsx
│   │       │   ├── MessageBubble.tsx
│   │       │   ├── ModelSelector.tsx
│   │       │   ├── LandingHero.tsx
│   │       │   ├── ToranAnimation.tsx
│   │       │   ├── SamosaIllustration.tsx
│   │       │   └── LoginCard.tsx
│   │       ├── hooks/
│   │       │   ├── useChat.ts
│   │       │   ├── useAuth.ts
│   │       │   └── useSSE.ts
│   │       ├── lib/
│   │       │   ├── api.ts
│   │       │   └── auth.ts
│   │       └── styles/
│   │           └── globals.css        # samosaChaat theme tokens
│   ├── auth/                          # Auth microservice (FastAPI)
│   │   ├── Dockerfile
│   │   ├── pyproject.toml
│   │   ├── src/
│   │   │   ├── main.py               # FastAPI app
│   │   │   ├── config.py             # Settings (env-based)
│   │   │   ├── routes/
│   │   │   │   ├── oauth.py          # Google/GitHub OAuth flows
│   │   │   │   ├── session.py        # JWT token management
│   │   │   │   └── users.py          # User profile CRUD
│   │   │   ├── models/
│   │   │   │   └── user.py           # SQLAlchemy User model
│   │   │   ├── services/
│   │   │   │   ├── google_oauth.py
│   │   │   │   ├── github_oauth.py
│   │   │   │   └── jwt_service.py
│   │   │   └── middleware/
│   │   │       └── auth_middleware.py # JWT validation middleware
│   │   └── tests/
│   ├── chat-api/                      # Chat orchestration microservice (FastAPI)
│   │   ├── Dockerfile
│   │   ├── pyproject.toml
│   │   ├── src/
│   │   │   ├── main.py
│   │   │   ├── config.py
│   │   │   ├── routes/
│   │   │   │   ├── conversations.py   # CRUD conversations
│   │   │   │   ├── messages.py        # Send/receive messages
│   │   │   │   └── models.py         # List available models
│   │   │   ├── models/
│   │   │   │   ├── conversation.py   # SQLAlchemy: conversations table
│   │   │   │   └── message.py        # SQLAlchemy: messages table
│   │   │   ├── services/
│   │   │   │   ├── conversation_service.py
│   │   │   │   ├── inference_client.py  # gRPC/HTTP client to inference svc
│   │   │   │   └── stream_proxy.py      # SSE proxy from inference → client
│   │   │   └── middleware/
│   │   │       └── auth_guard.py     # Validates JWT from auth service
│   │   ├── alembic/                   # DB migrations
│   │   │   ├── alembic.ini
│   │   │   ├── env.py
│   │   │   └── versions/
│   │   │       └── 001_initial_schema.py
│   │   └── tests/
│   └── inference/                     # Model inference microservice (FastAPI)
│       ├── Dockerfile
│       ├── pyproject.toml
│       ├── src/
│       │   ├── main.py
│       │   ├── config.py
│       │   ├── routes/
│       │   │   ├── generate.py        # POST /generate (SSE streaming)
│       │   │   ├── health.py          # Health + readiness probes
│       │   │   └── models.py          # List/swap model weights
│       │   ├── engine/                # Extracted from nanochat/
│       │   │   ├── gpt.py             # GPT model (from nanochat/gpt.py)
│       │   │   ├── engine.py          # Inference engine (from nanochat/engine.py)
│       │   │   ├── tokenizer.py       # Tokenizer (from nanochat/tokenizer.py)
│       │   │   ├── checkpoint.py      # Weight loading (from checkpoint_manager.py)
│       │   │   ├── flash_attention.py
│       │   │   └── fp8.py
│       │   ├── services/
│       │   │   ├── worker_pool.py     # GPU worker pool management
│       │   │   ├── weight_manager.py  # Hot-swap model weights (S3/HF)
│       │   │   └── tools.py           # Tool execution (calculator, etc.)
│       │   └── middleware/
│       │       └── internal_auth.py   # Service-to-service auth (API key)
│       └── tests/
├── contracts/                         # Shared API definitions
│   ├── openapi/
│   │   ├── auth-api.yaml
│   │   ├── chat-api.yaml
│   │   └── inference-api.yaml
│   └── schemas/
│       ├── user.json
│       ├── conversation.json
│       └── message.json
├── db/
│   └── migrations/                    # Alembic migrations (shared)
│       ├── alembic.ini
│       ├── env.py
│       └── versions/
│           ├── 001_create_users.py
│           ├── 002_create_conversations.py
│           └── 003_create_messages.py
├── scripts/
│   ├── local-dev.sh                   # docker-compose up for local dev
│   └── seed-db.sh                     # Seed test data
├── docker-compose.yml                 # Local development stack
├── docker-compose.override.yml        # Local overrides (hot reload)
├── .env.example
├── CLAUDE.md
└── README.md
```

---

## 2. Application Architecture Overview

```
                         ┌──────────────────────────────────────────────────────────┐
                         │                    AWS VPC (10.0.0.0/16)                 │
                         │                                                          │
     samosachaat.art     │  ┌─────────────┐    ┌──────────────────────────────────┐ │
    ─────────────────────┼─►│ ALB Ingress  │───►│        EKS Cluster               │ │
     (Route53 + ACM SSL) │  │ (HTTPS:443)  │    │                                  │ │
                         │  └─────────────┘    │  ┌───────────┐  ┌────────────┐   │ │
                         │                      │  │ Frontend  │  │  Auth Svc  │   │ │
                         │                      │  │ (Next.js) │  │ (FastAPI)  │   │ │
                         │                      │  │  :3000    │  │  :8001     │   │ │
                         │                      │  └─────┬─────┘  └──────┬─────┘   │ │
                         │                      │        │               │          │ │
                         │                      │  ┌─────▼───────────────▼─────┐   │ │
                         │                      │  │     Chat API Service      │   │ │
                         │                      │  │     (FastAPI) :8002        │   │ │
                         │                      │  └──────────────┬────────────┘   │ │
                         │                      │                 │                 │ │
                         │                      │  ┌──────────────▼────────────┐   │ │
                         │                      │  │   Inference Service       │   │ │
                         │                      │  │   (FastAPI) :8003         │   │ │
                         │                      │  │   [Model Weights on EFS]  │   │ │
                         │                      │  └──────────────────────────┘   │ │
                         │                      │                                  │ │
                         │                      │  ┌──────────────────────────┐   │ │
                         │                      │  │  Observability Stack      │   │ │
                         │                      │  │  Prometheus + Grafana     │   │ │
                         │                      │  │  Loki + Promtail          │   │ │
                         │                      │  └──────────────────────────┘   │ │
                         │                      └──────────────────────────────────┘ │
                         │                                     │                     │
                         │                      ┌──────────────▼──────────────┐     │
                         │                      │    AWS RDS (PostgreSQL)      │     │
                         │                      │    Private Subnet            │     │
                         │                      │    - users                   │     │
                         │                      │    - conversations           │     │
                         │                      │    - messages                │     │
                         │                      └─────────────────────────────┘     │
                         └──────────────────────────────────────────────────────────┘
```

**Request Flow:**
```
User → ALB (HTTPS) → Ingress Controller → Frontend (Next.js SSR)
                                        → /api/auth/*    → Auth Service
                                        → /api/chat/*    → Chat API Service → Inference Service
                                        → /api/models/*  → Chat API Service → Inference Service
```

**Deployment Strategy: Blue/Green**
- Justification: samosaChaat is a stateful chat application. Blue/Green gives us instant rollback (just flip the ALB target group), which is critical when model inference or DB schema changes break things. Canary is harder to reason about with SSE streaming connections — a user mid-conversation could get routed to a different version. Blue/Green avoids this entirely.

---

## Workstream A — Frontend Service

**Owner**: Frontend Agent
**Dependencies**: Needs API contracts from Workstreams B, C. No blocking dependencies for UI implementation.
**Estimated effort**: 2-3 days

### What to build

A **Next.js 14** (App Router) application that replaces the current `nanochat/ui.html` single-file UI. The design must blend Sarvam's clean, professional layout with samosaChaat's warm desi personality.

### Design System — samosaChaat Brand Tokens

**Carry forward from existing `ui.html`:**
```css
/* Colors */
--sc-gold: #e8a838;
--sc-gold-light: #f5d799;
--sc-brown: #8b4d0a;
--sc-brown-dark: #5a3206;
--sc-cream: #fff8e7;
--sc-cream-dark: #f5edd6;
--sc-chutney: #2d8a4e;
--sc-chutney-light: #e8f5ed;
--sc-red: #c0392b;
--sc-white: #ffffff;
--sc-text: #3d2b1f;
--sc-text-muted: #8b7355;
--sc-border: rgba(139,77,10,0.12);

/* Typography */
--font-display: 'Baloo 2', cursive;       /* Headings, brand name (Devanagari-capable) */
--font-cursive: 'Great Vibes', cursive;    /* English brand logotype */
--font-body: 'Inter', system-ui, sans-serif; /* Body text (replace Caveat for readability) */
--font-mono: 'JetBrains Mono', monospace;  /* Code blocks */

/* Spacing */
--radius-sm: 8px;
--radius-md: 12px;
--radius-lg: 20px;
--radius-full: 9999px;
```

### Page-by-Page Specification

#### A1. Landing Page (`/`)
- **Layout**: Full-viewport hero, no sidebar
- **Top nav**: samosaChaat logo (SVG) + toran animation (lemon-mirchi pendulum, already built in ui.html CSS) + "Login" button (top-right, `--sc-gold` background, `--sc-brown` text)
- **Hero section**:
  - Devanagari calligraphy: "समोसाचाट" (large, `Baloo 2`, gold-brown gradient)
  - English script: "samosaChaat" below in `Great Vibes` (overlapping slightly, as in current ui.html)
  - Tagline: "Your AI, with a dash of masala" (Inter, muted brown)
  - CTA button: "Start Chatting" → redirects to `/login` if not authenticated, `/chat` if authenticated
- **Illustrations**: Port the watercolor samosa SVG (left, float animation) and chai kettle SVG (right, wobble + steam wisps) from current `ui.html`
- **Ambient doodles**: 5 floating lemon/chilli decorations (existing CSS keyframes)
- **Footer**: "Crafted with care. For India, from India." (as in Sarvam's style)

#### A2. Login Page (`/login`)
- **Layout**: Split-screen (like Sarvam's login screenshot)
  - **Left half**: Full-bleed image — use a warm, Indian architectural motif (Rajasthani archway or jharokha window) with the samosaChaat geometric mandala/lotus overlay (like Sarvam does with their logo). Background: warm saffron-to-cream gradient.
  - **Right half**: White card, centered:
    - "Login to your account" (Baloo 2, `--sc-brown`)
    - Google OAuth button (standard Google branding)
    - GitHub OAuth button (GitHub mark + "GitHub" label)
    - Divider: "OR"
    - Email input + "Continue" button (for future email/password, disabled MVP)
    - "Don't have an account? Create one" link
    - Footer: samosaChaat logo small + "Crafted with care"
- **Responsive**: On mobile, stack vertically — image on top (cropped to 40vh), login card below

#### A3. Chat Page (`/chat`)
- **Layout**: Sarvam-style sidebar + main content
  - **Sidebar (left, 260px, collapsible)**:
    - samosaChaat logo (top)
    - "+ New Chat" button (`--sc-gold` accent)
    - **Conversation history list** (grouped: Today, Yesterday, Last 7 days, Older)
      - Each item: truncated first message, timestamp, delete button on hover
    - **Divider**
    - **Model selector dropdown** (bottom of sidebar): shows available models with swap capability
    - User avatar + name (bottom) with logout
  - **Main chat area**:
    - **Header bar**: "Chat Completions" title + "New Chat" button (like Sarvam)
    - **Empty state** (no messages): centered "How can I help you today?" (Baloo 2, large) with suggestion chips below:
      - "Summarize a topic" | "Explain a concept" | "Write some code" | "Tell me a joke"
    - **Messages area**: scrollable, messages alternate:
      - User bubbles: right-aligned, `--sc-cream` background, `--sc-brown` text, `--radius-lg`
      - Assistant bubbles: left-aligned, white background, subtle `--sc-border`, markdown rendered
      - Code blocks: `--sc-brown-dark` background, `--font-mono`, copy button
    - **Input area** (bottom, sticky):
      - Textarea with placeholder "What's on your mind?" (from current ui.html)
      - Auto-expanding (up to 200px), then scrollable
      - Send button (circle, `--sc-gold`, arrow icon)
      - Slash command support: `/temperature`, `/topk`, `/clear`, `/model`
    - **Streaming**: SSE with steam typing indicator (4 animated bars, port from current ui.html CSS)

#### A4. Settings Page (`/settings`) — Stretch
- Model management (view loaded models, trigger weight swap)
- Account settings (name, avatar)
- API key management (future)

### Tech Stack

| Layer | Choice | Why |
|-------|--------|-----|
| Framework | Next.js 14 (App Router) | SSR for landing/login, CSR for chat. Built-in API routes for BFF pattern |
| Styling | Tailwind CSS + CSS variables | Utility-first + theme tokens. No component library overhead |
| State | Zustand | Lightweight, no boilerplate. Perfect for chat state |
| Auth | NextAuth.js v5 | Google + GitHub providers, JWT sessions, middleware protection |
| SSE | Native EventSource + custom hook | No library needed, browser-native |
| Icons | Lucide React | Clean, consistent |
| Animations | Framer Motion | Landing page transitions, sidebar collapse, message entry |
| Fonts | Google Fonts (Baloo 2, Great Vibes, Inter) | Already used in current ui.html |

### Dockerfile

```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/public ./public
COPY --from=builder /app/package.json ./
COPY --from=builder /app/node_modules ./node_modules
EXPOSE 3000
CMD ["npm", "start"]
```

### Key Implementation Notes for Agent

1. **Port all SVG assets** from `nanochat/ui.html` and `nanochat/logo.svg` into `public/`
2. **Port all CSS animations** (toran swing, samosa float, chai wobble, steam indicator) into Tailwind `@keyframes` or Framer Motion
3. **The SSE streaming hook** must handle the existing response format: `data: {"token": "...", "gpu": 0}` and `data: {"done": true}`
4. **NextAuth.js** handles OAuth — but the actual user creation/lookup happens via the Auth Service API. NextAuth calls Auth Service on sign-in to create/fetch user.
5. **All API calls** go through Next.js API routes (BFF pattern) → backend services. Frontend never calls backend services directly.
6. **Environment variables needed**: `NEXT_PUBLIC_APP_URL`, `AUTH_SERVICE_URL`, `CHAT_API_URL`, `NEXTAUTH_SECRET`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET`

---

## Workstream B — Auth Service

**Owner**: Backend Agent 1
**Dependencies**: Needs RDS connection string from Workstream E/F. Can develop against local PostgreSQL.
**Estimated effort**: 1-2 days

### What to build

A FastAPI microservice handling OAuth2 authentication (Google, GitHub), JWT token issuance, and user profile management.

### Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/auth/google` | None | Redirect to Google OAuth consent screen |
| GET | `/auth/google/callback` | None | Handle Google OAuth callback, create/find user, return JWT |
| GET | `/auth/github` | None | Redirect to GitHub OAuth consent screen |
| GET | `/auth/github/callback` | None | Handle GitHub OAuth callback, create/find user, return JWT |
| POST | `/auth/refresh` | Refresh token | Issue new access token |
| GET | `/auth/me` | Bearer JWT | Return current user profile |
| PUT | `/auth/me` | Bearer JWT | Update user profile (name, avatar) |
| GET | `/auth/health` | None | Health check |
| POST | `/auth/validate` | Internal API key | Validate JWT and return user — used by other services |

### Database Tables (owned by Auth Service)

```sql
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           VARCHAR(255) UNIQUE NOT NULL,
    name            VARCHAR(255),
    avatar_url      TEXT,
    provider        VARCHAR(50) NOT NULL,        -- 'google' | 'github'
    provider_id     VARCHAR(255) NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    last_login_at   TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(provider, provider_id)
);
```

### JWT Structure

```json
{
  "sub": "user-uuid",
  "email": "manmohan659@gmail.com",
  "name": "Manmohan Sharma",
  "iat": 1713200000,
  "exp": 1713203600,
  "iss": "samosachaat-auth"
}
```

- **Access token**: 1 hour expiry, RS256 signed
- **Refresh token**: 7 day expiry, stored in httpOnly cookie

### Tech Stack

| Layer | Choice |
|-------|--------|
| Framework | FastAPI + Uvicorn |
| ORM | SQLAlchemy 2.0 (async) + asyncpg |
| Migrations | Alembic (shared with Chat API) |
| OAuth | authlib |
| JWT | PyJWT + cryptography (RS256) |
| Config | pydantic-settings |

### Environment Variables

```
DATABASE_URL=postgresql+asyncpg://user:pass@rds-host:5432/samosachaat
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
GITHUB_CLIENT_ID=...
GITHUB_CLIENT_SECRET=...
JWT_PRIVATE_KEY=...          # RS256 private key (PEM)
JWT_PUBLIC_KEY=...           # RS256 public key (shared with other services)
FRONTEND_URL=https://samosachaat.art
INTERNAL_API_KEY=...         # For service-to-service /auth/validate calls
```

### Dockerfile

```dockerfile
FROM python:3.12-slim
WORKDIR /app
RUN pip install uv
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen
COPY src/ ./src/
EXPOSE 8001
CMD ["uv", "run", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8001"]
```

### Key Notes for Agent

1. Google OAuth: Use `authlib` with discovery URL `https://accounts.google.com/.well-known/openid-configuration`
2. GitHub OAuth: Authorization URL `https://github.com/login/oauth/authorize`, token URL `https://github.com/login/oauth/access_token`
3. On OAuth callback: upsert user (create if new, update last_login if existing), then issue JWT
4. The `/auth/validate` endpoint is **internal only** — called by Chat API service to validate incoming JWTs without each service needing the JWT public key. Secured by `INTERNAL_API_KEY` header.
5. CORS: Allow `FRONTEND_URL` only (not `*`)
6. Rate limit: 10 login attempts per minute per IP (use `slowapi`)

---

## Workstream C — Chat API Service

**Owner**: Backend Agent 2
**Dependencies**: Needs Auth Service API contract (Workstream B), Inference Service API contract (Workstream D), RDS connection (Workstream E/F). Can develop against local PostgreSQL + mocked inference.
**Estimated effort**: 2-3 days

### What to build

The orchestration layer. Manages conversations, persists messages to RDS, proxies streaming inference requests, and enforces user-scoped access control.

### Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/conversations` | Bearer JWT | List user's conversations (paginated) |
| POST | `/api/conversations` | Bearer JWT | Create new conversation |
| GET | `/api/conversations/:id` | Bearer JWT | Get conversation with messages |
| DELETE | `/api/conversations/:id` | Bearer JWT | Delete conversation |
| PUT | `/api/conversations/:id` | Bearer JWT | Update title |
| POST | `/api/conversations/:id/messages` | Bearer JWT | Send message + get streaming response |
| POST | `/api/conversations/:id/regenerate` | Bearer JWT | Regenerate last assistant message |
| GET | `/api/models` | Bearer JWT | List available models (proxied from inference) |
| POST | `/api/models/swap` | Bearer JWT (admin) | Hot-swap model weights |
| GET | `/api/health` | None | Health check |

### Database Tables (owned by Chat API Service)

```sql
CREATE TABLE conversations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title           VARCHAR(500),                -- Auto-generated from first message
    model_tag       VARCHAR(100) DEFAULT 'default',
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_conversations_user ON conversations(user_id, updated_at DESC);

CREATE TABLE messages (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    role            VARCHAR(20) NOT NULL,        -- 'user' | 'assistant' | 'system'
    content         TEXT NOT NULL,
    token_count     INTEGER,
    model_tag       VARCHAR(100),
    inference_time_ms INTEGER,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_messages_conversation ON messages(conversation_id, created_at ASC);
```

### Message Send Flow (POST `/api/conversations/:id/messages`)

```
1. Validate JWT → extract user_id
2. Verify conversation belongs to user
3. Save user message to DB
4. Fetch conversation history from DB (last N messages, within token budget)
5. Build chat payload: [{role, content}, ...]
6. POST to Inference Service /generate (SSE)
7. Stream tokens back to client via SSE
8. On stream complete: save full assistant response to DB
9. If first message: auto-generate conversation title (first 50 chars of user message)
```

### Tech Stack

| Layer | Choice |
|-------|--------|
| Framework | FastAPI + Uvicorn |
| ORM | SQLAlchemy 2.0 (async) + asyncpg |
| Migrations | Alembic |
| HTTP client | httpx (async, for calling inference service) |
| SSE | sse-starlette |
| Config | pydantic-settings |
| Logging | structlog (JSON structured logs) |

### Environment Variables

```
DATABASE_URL=postgresql+asyncpg://user:pass@rds-host:5432/samosachaat
AUTH_SERVICE_URL=http://auth-service:8001
INFERENCE_SERVICE_URL=http://inference-service:8003
INTERNAL_API_KEY=...
MAX_CONVERSATION_HISTORY=50    # Max messages sent to inference
MAX_TOKEN_BUDGET=6000          # Max tokens in context
```

### Dockerfile

```dockerfile
FROM python:3.12-slim
WORKDIR /app
RUN pip install uv
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen
COPY src/ ./src/
COPY alembic/ ./alembic/
COPY alembic.ini .
EXPOSE 8002
CMD ["uv", "run", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8002"]
```

### Key Notes for Agent

1. **Auth validation**: On every request, extract `Authorization: Bearer <jwt>` header, call Auth Service `POST /auth/validate` to get user object. Cache the validation result for 5 minutes (in-memory LRU).
2. **SSE proxy**: Use `httpx` async streaming to call inference service. Yield each chunk as SSE event to the client. Accumulate tokens into a buffer. On stream completion, flush the accumulated response to DB.
3. **Title generation**: For the first message in a conversation, set `title = user_message[:80]`. Don't use the model for title generation (too expensive for this scale).
4. **Conversation scoping**: Every DB query must include `WHERE user_id = :user_id` to prevent cross-user data access.
5. **Alembic migrations**: Run as an init container in K8s (before the main container starts). See Helm chart notes.

---

## Workstream D — Inference Service

**Owner**: ML/Backend Agent 3
**Dependencies**: Needs model weights (HuggingFace or S3). No dependency on other services.
**Estimated effort**: 1-2 days (mostly extraction + weight swap feature)

### What to build

Extract the existing nanochat inference engine into a standalone microservice. Add model weight hot-swapping capability.

### What to extract from existing code

| Source file | Destination | Changes |
|-------------|-------------|---------|
| `nanochat/gpt.py` | `services/inference/src/engine/gpt.py` | No changes |
| `nanochat/engine.py` | `services/inference/src/engine/engine.py` | No changes |
| `nanochat/tokenizer.py` | `services/inference/src/engine/tokenizer.py` | No changes |
| `nanochat/checkpoint_manager.py` | `services/inference/src/engine/checkpoint.py` | Add S3/EFS weight loading |
| `nanochat/common.py` | `services/inference/src/engine/common.py` | No changes |
| `nanochat/flash_attention.py` | `services/inference/src/engine/flash_attention.py` | No changes |
| `nanochat/fp8.py` | `services/inference/src/engine/fp8.py` | No changes |
| `nanochat/tools.py` | `services/inference/src/services/tools.py` | No changes |
| `nanochat/execution.py` | `services/inference/src/services/execution.py` | No changes |
| `scripts/chat_web.py` | `services/inference/src/main.py` | Refactor: remove UI serving, keep worker pool + generation |

### Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/generate` | Internal API key | Streaming token generation (SSE) |
| GET | `/models` | Internal API key | List loaded models + available weights |
| POST | `/models/swap` | Internal API key | Hot-swap model weights |
| GET | `/health` | None | Health check (ready = model loaded) |
| GET | `/stats` | Internal API key | Worker pool stats (GPU utilization) |

### Model Weight Hot-Swap Design

```python
# Weight manager maintains a registry of available models
# Stored on EFS (shared across pods) or downloaded from HuggingFace/S3

WEIGHT_REGISTRY = {
    "samosachaat-d12": {
        "path": "/models/d12/model_latest.pt",
        "config": "/models/d12/meta_latest.json",
        "source": "huggingface:manmohan659/samosachaat-d12",
        "loaded": True,
        "gpu_memory_mb": 450
    },
    "samosachaat-d24": {
        "path": "/models/d24/model_latest.pt",
        "source": "huggingface:manmohan659/samosachaat-d24",
        "loaded": False,
        "gpu_memory_mb": 2700
    }
}

# POST /models/swap {"model_tag": "samosachaat-d24"}
# 1. Download weights if not on disk
# 2. Drain current worker pool (wait for in-flight requests)
# 3. Unload current model from GPU memory
# 4. Load new model
# 5. Rebuild worker pool
# 6. Return success
```

### Environment Variables

```
MODEL_STORAGE_PATH=/models                  # EFS mount or local path
DEFAULT_MODEL_TAG=samosachaat-d12
HF_TOKEN=...                               # For downloading from HuggingFace
INTERNAL_API_KEY=...
NANOCHAT_DTYPE=float32                      # For CPU inference (auto-detected on GPU)
NUM_WORKERS=1                               # Workers per GPU
```

### Dockerfile

```dockerfile
FROM python:3.12-slim
WORKDIR /app

# Install PyTorch (CPU by default, GPU variant via build arg)
ARG TORCH_INDEX=https://download.pytorch.org/whl/cpu
RUN pip install uv

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen
COPY src/ ./src/

EXPOSE 8003
CMD ["uv", "run", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8003"]
```

### Key Notes for Agent

1. **This is the only service that touches PyTorch/model code.** All other services are pure web/DB.
2. **Worker pool**: Port directly from `scripts/chat_web.py` lines 40-120. The async queue + worker checkout/checkin pattern is already production-quality.
3. **Request format stays the same**: `ChatRequest(messages, temperature, max_tokens, top_k)` — the Chat API service builds this.
4. **Health check must report model readiness**: K8s readiness probe depends on this. Return `{"ready": false}` while model is loading.
5. **For EKS deployment without GPUs** (dev/UAT): use CPU inference with `NANOCHAT_DTYPE=float32` and a small model (d12). Prod can use GPU nodes.
6. **Weight files go on EFS** (Elastic File System) mounted at `/models` — shared across inference pods so you don't download per-pod.

---

## Workstream E — Database & Schema Management

**Owner**: Any backend agent (can be done by Workstream B or C agent)
**Dependencies**: RDS instance from Workstream F (Terraform). Can develop against local PostgreSQL.
**Estimated effort**: 0.5 days

### Database Design

**Engine**: PostgreSQL 15 (AWS RDS)
**Database name**: `samosachaat`

### Full Schema

```sql
-- Owned by Auth Service
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           VARCHAR(255) UNIQUE NOT NULL,
    name            VARCHAR(255),
    avatar_url      TEXT,
    provider        VARCHAR(50) NOT NULL,
    provider_id     VARCHAR(255) NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    last_login_at   TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(provider, provider_id)
);

-- Owned by Chat API Service
CREATE TABLE conversations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title           VARCHAR(500),
    model_tag       VARCHAR(100) DEFAULT 'default',
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_conversations_user ON conversations(user_id, updated_at DESC);

CREATE TABLE messages (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    role            VARCHAR(20) NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
    content         TEXT NOT NULL,
    token_count     INTEGER,
    model_tag       VARCHAR(100),
    inference_time_ms INTEGER,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_messages_conversation ON messages(conversation_id, created_at ASC);
```

### Migration Strategy (Alembic)

```
db/migrations/
├── alembic.ini
├── env.py
└── versions/
    ├── 001_create_users.py
    ├── 002_create_conversations.py
    └── 003_create_messages.py
```

**How migrations run in K8s:**
- Alembic runs as a **Kubernetes Job** (init container pattern) before the main service pods start
- The Helm chart includes a `pre-install` and `pre-upgrade` hook Job:
  ```yaml
  apiVersion: batch/v1
  kind: Job
  metadata:
    name: db-migrate
    annotations:
      "helm.sh/hook": pre-install,pre-upgrade
      "helm.sh/hook-weight": "-1"
      "helm.sh/hook-delete-policy": hook-succeeded
  spec:
    template:
      spec:
        containers:
        - name: migrate
          image: {{ .Values.chatApi.image }}
          command: ["alembic", "upgrade", "head"]
          env:
          - name: DATABASE_URL
            valueFrom:
              secretKeyRef:
                name: samosachaat-db
                key: url
        restartPolicy: Never
  ```

### Day 2: Schema Change Demonstration

**Scenario**: Add a `is_favorited` column to conversations.

```python
# db/migrations/versions/004_add_favorited.py
def upgrade():
    op.add_column('conversations',
        sa.Column('is_favorited', sa.Boolean(), server_default='false', nullable=False))

def downgrade():
    op.drop_column('conversations', 'is_favorited')
```

**Process:**
1. Create migration: `alembic revision --autogenerate -m "add is_favorited"`
2. Commit with conventional commit: `feat(db): add is_favorited column to conversations`
3. CI pipeline builds new Chat API image
4. Helm upgrade triggers the migration Job first
5. `ALTER TABLE conversations ADD COLUMN is_favorited BOOLEAN DEFAULT false NOT NULL;` runs
6. New pods start with updated SQLAlchemy models
7. **Zero downtime**: Adding a nullable/default column is a non-blocking DDL in PostgreSQL. Old pods ignore the new column. New pods use it.

---

## Workstream F — Terraform / Infrastructure

**Owner**: Infrastructure Agent
**Dependencies**: AWS account, Route53 hosted zone for `samosachaat.art`. No code dependencies.
**Estimated effort**: 2-3 days

### What to provision

| Resource | Terraform Module | Details |
|----------|-----------------|---------|
| VPC | `modules/vpc` | 3 AZs, public + private subnets, NAT gateway |
| EKS | `modules/eks` | v1.29, managed node groups (t3.large for dev, t3.xlarge for prod) |
| RDS | `modules/rds` | PostgreSQL 15, db.t3.micro (dev), db.t3.medium (prod), private subnet |
| ECR | `modules/ecr` | 4 repos: frontend, auth, chat-api, inference |
| IAM | `modules/iam` | EKS node role, ALB controller role, ECR pull policy |
| Route53 | `modules/route53` | A record → ALB, ACM certificate validation |
| ACM | `modules/acm` | SSL certificate for `samosachaat.art` + `*.samosachaat.art` |
| EFS | `modules/efs` | Model weights storage, mounted by inference pods |
| S3 | (backend) | Terraform state bucket + DynamoDB lock table |

### Module Structure

```hcl
# terraform/modules/vpc/main.tf
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "samosachaat-${var.environment}"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = var.environment == "dev" ? true : false
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}
```

```hcl
# terraform/modules/eks/main.tf
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "samosachaat-${var.environment}"
  cluster_version = "1.29"

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]
      min_size       = var.min_nodes
      max_size       = var.max_nodes
      desired_size   = var.desired_nodes

      labels = { role = "app" }
    }
  }

  # ALB Ingress Controller IRSA
  enable_irsa = true
}
```

```hcl
# terraform/modules/rds/main.tf
module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  identifier     = "samosachaat-${var.environment}"
  engine         = "postgres"
  engine_version = "15"
  instance_class = var.db_instance_class

  allocated_storage = 20
  db_name           = "samosachaat"
  username          = "samosachaat_admin"

  vpc_security_group_ids = [var.db_security_group_id]
  subnet_ids             = var.private_subnet_ids
  create_db_subnet_group = true

  # Backups
  backup_retention_period = 7
  skip_final_snapshot     = var.environment == "dev"
}
```

### Environment Configs

```hcl
# terraform/environments/dev/main.tf
module "infrastructure" {
  source = "../../modules"

  environment        = "dev"
  node_instance_type = "t3.large"
  min_nodes          = 2
  max_nodes          = 4
  desired_nodes      = 2
  db_instance_class  = "db.t3.micro"
}

# terraform/environments/prod/main.tf
module "infrastructure" {
  source = "../../modules"

  environment        = "prod"
  node_instance_type = "t3.xlarge"
  min_nodes          = 3
  max_nodes          = 10
  desired_nodes      = 3
  db_instance_class  = "db.t3.medium"
}
```

### State Management

```hcl
# terraform/backend.tf
terraform {
  backend "s3" {
    bucket         = "samosachaat-terraform-state"
    key            = "infrastructure/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "samosachaat-terraform-locks"
    encrypt        = true
  }
}
```

### Day 1 → Day 2 Automation

- **Day 1**: `terraform init && terraform apply` — provisions everything from scratch
- **Day 2**: Same `terraform apply` — updates in place. EKS node group updates trigger rolling replacement. RDS changes apply during maintenance window.

### Key Notes for Agent

1. **Create the S3 state bucket and DynamoDB lock table manually first** (bootstrap — can't manage its own backend)
2. **ACM certificate validation**: Use Route53 DNS validation (automated). Terraform creates the cert and the validation CNAME records.
3. **EKS add-ons to install**: AWS Load Balancer Controller (for ALB Ingress), EBS CSI Driver, EFS CSI Driver, CoreDNS, kube-proxy
4. **Security groups**: RDS only accessible from EKS node security group. EKS nodes in private subnets. ALB in public subnets.
5. **Outputs**: Export VPC ID, subnet IDs, EKS cluster name, RDS endpoint, ECR repo URLs — needed by CI/CD pipeline.

---

## Workstream G — CI/CD Pipeline

**Owner**: DevOps Agent
**Dependencies**: Terraform outputs (ECR URLs, EKS cluster name). Can build pipeline structure without them.
**Estimated effort**: 1-2 days

### Promotion Flow

```
   Push to feature branch          Merge to main           Tag RC1              Tag v1.0.0
          │                            │                      │                     │
          ▼                            ▼                      ▼                     ▼
   ┌──────────────┐            ┌──────────────┐       ┌──────────────┐      ┌──────────────┐
   │  CI: Lint +  │            │  Build Docker │       │ Deploy to    │      │ Deploy to    │
   │  Test + Type │            │  images, push │       │ UAT cluster  │      │ PROD cluster │
   │  Check       │            │  to ECR :dev  │       │ (Blue/Green) │      │ (Blue/Green) │
   └──────────────┘            └──────┬───────┘       └──────────────┘      └──────────────┘
                                      │
                                      ▼
                               ┌──────────────┐
                               │ Nightly: Full │
                               │ integration   │
                               │ test suite    │
                               │ → QA env      │
                               └──────────────┘
```

### GitHub Actions Workflows

#### G1. `ci.yml` — Continuous Integration (every push/PR)

```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main]

jobs:
  changes:
    runs-on: ubuntu-latest
    outputs:
      frontend: ${{ steps.changes.outputs.frontend }}
      auth: ${{ steps.changes.outputs.auth }}
      chat-api: ${{ steps.changes.outputs.chat-api }}
      inference: ${{ steps.changes.outputs.inference }}
      terraform: ${{ steps.changes.outputs.terraform }}
    steps:
      - uses: dorny/paths-filter@v3
        id: changes
        with:
          filters: |
            frontend: 'services/frontend/**'
            auth: 'services/auth/**'
            chat-api: 'services/chat-api/**'
            inference: 'services/inference/**'
            terraform: 'terraform/**'

  test-frontend:
    needs: changes
    if: needs.changes.outputs.frontend == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: cd services/frontend && npm ci && npm run lint && npm run type-check && npm test

  test-auth:
    needs: changes
    if: needs.changes.outputs.auth == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: cd services/auth && pip install uv && uv sync && uv run pytest

  test-chat-api:
    needs: changes
    if: needs.changes.outputs.chat-api == 'true'
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_DB: samosachaat_test
          POSTGRES_PASSWORD: test
        ports: ['5432:5432']
    steps:
      - uses: actions/checkout@v4
      - run: cd services/chat-api && pip install uv && uv sync && uv run pytest

  test-inference:
    needs: changes
    if: needs.changes.outputs.inference == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: cd services/inference && pip install uv && uv sync && uv run pytest

  terraform-validate:
    needs: changes
    if: needs.changes.outputs.terraform == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - run: cd terraform && terraform init -backend=false && terraform validate
```

#### G2. `build-dev.yml` — Build & Push to ECR (merge to main)

```yaml
name: Build Dev
on:
  push:
    branches: [main]

jobs:
  build:
    strategy:
      matrix:
        service: [frontend, auth, chat-api, inference]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
      - uses: aws-actions/amazon-ecr-login@v2
      - run: |
          docker build -t $ECR_REGISTRY/samosachaat-${{ matrix.service }}:dev-${{ github.sha }} services/${{ matrix.service }}
          docker push $ECR_REGISTRY/samosachaat-${{ matrix.service }}:dev-${{ github.sha }}
```

#### G3. `promote-uat.yml` — Deploy to UAT (RC tags)

```yaml
name: Promote to UAT
on:
  push:
    tags: ['RC*']    # RC1, RC2, RC3, ...

jobs:
  deploy-uat:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
      - run: aws eks update-kubeconfig --name samosachaat-uat
      - run: |
          # Re-tag dev images as UAT
          for svc in frontend auth chat-api inference; do
            docker pull $ECR_REGISTRY/samosachaat-$svc:dev-${{ github.sha }}
            docker tag $ECR_REGISTRY/samosachaat-$svc:dev-${{ github.sha }} $ECR_REGISTRY/samosachaat-$svc:uat-${{ github.ref_name }}
            docker push $ECR_REGISTRY/samosachaat-$svc:uat-${{ github.ref_name }}
          done
      - run: |
          helm upgrade --install samosachaat helm/samosachaat \
            -f helm/samosachaat/values-uat.yaml \
            --set global.imageTag=uat-${{ github.ref_name }} \
            --namespace samosachaat-uat --create-namespace \
            --wait --timeout 10m
```

#### G4. `release-prod.yml` — Deploy to Prod (version tags)

```yaml
name: Release to Production
on:
  push:
    tags: ['v*']     # v1.0.0, v1.0.1, ...

jobs:
  deploy-prod:
    runs-on: ubuntu-latest
    environment: production    # Requires manual approval in GitHub settings
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
      - run: aws eks update-kubeconfig --name samosachaat-prod
      # Blue/Green: deploy to green, test, then swap
      - run: |
          # Deploy to green target group
          helm upgrade --install samosachaat-green helm/samosachaat \
            -f helm/samosachaat/values-prod.yaml \
            --set global.imageTag=prod-${{ github.ref_name }} \
            --set deployment.slot=green \
            --namespace samosachaat-prod \
            --wait --timeout 10m

          # Run smoke tests against green
          kubectl run smoke-test --image=curlimages/curl --restart=Never \
            -- curl -f http://samosachaat-green.samosachaat-prod.svc/health

          # Swap ALB target: blue → green
          kubectl patch ingress samosachaat-ingress -n samosachaat-prod \
            --type=json -p='[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service/name","value":"samosachaat-green"}]'

          # Previous blue becomes the new standby (keep for instant rollback)
```

#### G5. `nightly.yml` — Integration Tests

```yaml
name: Nightly QA
on:
  schedule:
    - cron: '0 6 * * *'    # 6 AM UTC daily

jobs:
  integration-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: docker compose -f docker-compose.yml -f docker-compose.test.yml up --abort-on-container-exit
```

### Conventional Commits Enforcement

```
feat(auth): add GitHub OAuth provider          → triggers build
fix(chat-api): handle empty conversation list  → triggers build
feat(db)!: add is_favorited column             → BREAKING, triggers UAT via RC tag
chore(ci): update Node version                 → no service rebuild
```

**Tooling**: `commitlint` + `husky` in repo root for local enforcement, GitHub Action check on PRs.

---

## Workstream H — Observability & Logging

**Owner**: DevOps/Observability Agent
**Dependencies**: EKS cluster from Workstream F. Can prepare Helm values/configs independently.
**Estimated effort**: 1-2 days

### Stack

| Component | Tool | Purpose |
|-----------|------|---------|
| Metrics | Prometheus (self-hosted on EKS) | Scrape CPU, memory, disk, request latency, model inference time |
| Dashboards | Grafana (self-hosted on EKS) | Visualize metrics, alerting rules |
| Logging | Loki + Promtail (self-hosted on EKS) | Centralized log aggregation from all 4 services |
| Alerting | Grafana Alerting → Email + Slack | CPU > 80%, Memory > 85%, Disk > 90%, 5xx rate > 5% |

### Prometheus Setup

```yaml
# helm/observability/values.yaml (kube-prometheus-stack)
prometheus:
  prometheusSpec:
    serviceMonitorSelector:
      matchLabels:
        app.kubernetes.io/part-of: samosachaat
    retention: 15d
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 50Gi
```

### Grafana Configuration

**Access**: External via ALB Ingress at `grafana.samosachaat.art`

**Authentication: OAuth2 ONLY (username/password disabled)**

```yaml
grafana:
  grafana.ini:
    auth:
      disable_login_form: true
    auth.github:
      enabled: true
      allow_sign_up: true
      client_id: ${GITHUB_OAUTH_CLIENT_ID}
      client_secret: ${GITHUB_OAUTH_CLIENT_SECRET}
      scopes: user:email,read:org
      auth_url: https://github.com/login/oauth/authorize
      token_url: https://github.com/login/oauth/access_token
      api_url: https://api.github.com/user
      allowed_organizations: samosachaat
    auth.google:
      enabled: true
      client_id: ${GOOGLE_OAUTH_CLIENT_ID}
      client_secret: ${GOOGLE_OAUTH_CLIENT_SECRET}
      scopes: openid email profile
      auth_url: https://accounts.google.com/o/oauth2/auth
      token_url: https://accounts.google.com/o/oauth2/token
      allowed_domains: gmail.com
    server:
      root_url: https://grafana.samosachaat.art
  ingress:
    enabled: true
    annotations:
      kubernetes.io/ingress.class: alb
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/certificate-arn: ${ACM_CERT_ARN}
    hosts:
      - grafana.samosachaat.art
```

### Grafana Dashboards (pre-provisioned)

**Dashboard 1: Node Health**
- CPU usage per node (gauge + time series)
- Memory usage per node (gauge + time series)
- Disk space per node (gauge)
- Network I/O
- Pod count per node

**Dashboard 2: Application Performance**
- Request rate per service (frontend, auth, chat-api, inference)
- Response time percentiles (p50, p95, p99) per service
- Error rate (4xx, 5xx) per service
- Active SSE connections
- Model inference latency histogram

**Dashboard 3: Inference Service**
- GPU memory utilization (if applicable)
- Model load time
- Tokens per second
- Worker pool utilization
- Active generation count

### Loki + Promtail Setup

```yaml
loki:
  persistence:
    enabled: true
    size: 50Gi
  config:
    limits_config:
      retention_period: 30d

promtail:
  config:
    scrape_configs:
      - job_name: kubernetes-pods
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_namespace]
            target_label: namespace
          - source_labels: [__meta_kubernetes_pod_name]
            target_label: pod
          - source_labels: [__meta_kubernetes_pod_label_app]
            target_label: app
```

### Application Logging Standard

All services must use **structured JSON logging** via `structlog` (Python) or `pino` (Node.js):

```json
{
  "timestamp": "2026-04-15T12:00:00Z",
  "level": "info",
  "service": "chat-api",
  "trace_id": "abc123",
  "user_id": "uuid",
  "message": "Message sent",
  "conversation_id": "uuid",
  "tokens_generated": 150,
  "inference_time_ms": 320
}
```

**Loki queries across services:**
```logql
{namespace="samosachaat-prod"} | json | trace_id="abc123"
{app=~"auth|chat-api|inference"} | json | level="error"
```

### Alert Rules

```yaml
groups:
  - name: samosachaat-alerts
    rules:
      - alert: HighCPU
        expr: avg(rate(node_cpu_seconds_total{mode!="idle"}[5m])) by (instance) > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "CPU > 80% on {{ $labels.instance }}"

      - alert: HighMemory
        expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) > 0.85
        for: 5m
        labels:
          severity: critical

      - alert: DiskSpaceLow
        expr: (1 - node_filesystem_avail_bytes / node_filesystem_size_bytes) > 0.9
        for: 10m
        labels:
          severity: critical

      - alert: High5xxRate
        expr: sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) > 0.05
        for: 2m
        labels:
          severity: critical

      - alert: InferenceServiceDown
        expr: up{job="inference-service"} == 0
        for: 1m
        labels:
          severity: critical
```

**Alert notification channels:**
- Email: via Grafana SMTP configuration
- Slack: via Grafana Slack webhook integration

---

## Workstream I — Day 2 Operations

**Owner**: Infrastructure Agent (same as Workstream F)
**Dependencies**: EKS cluster running
**Estimated effort**: 0.5 days (automation scripts + documentation)

### I1. OS/Security Patching (AMI Rotation)

**Strategy**: EKS Managed Node Group rolling update with PodDisruptionBudgets

```bash
# Step 1: Update the launch template with latest AMI
# Terraform handles this — just update the AMI ID or use "latest" AL2 AMI

# Step 2: Trigger node group update
aws eks update-nodegroup-version \
  --cluster-name samosachaat-prod \
  --nodegroup-name default \
  --launch-template name=samosachaat-prod,version=$LATEST

# EKS automatically:
# 1. Launches new nodes with updated AMI
# 2. Cordons old nodes (no new pods scheduled)
# 3. Drains old nodes (respecting PDBs — pods gracefully relocated)
# 4. Terminates old nodes
# 5. Zero downtime (PDBs ensure min replicas always running)
```

**PodDisruptionBudgets:**
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: chat-api-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: chat-api
```

**Terraform automation:**
```hcl
# Use aws_ami data source to always get latest EKS-optimized AMI
data "aws_ssm_parameter" "eks_ami" {
  name = "/aws/service/eks/optimized-ami/1.29/amazon-linux-2/recommended/image_id"
}

# Node group uses this AMI — terraform apply triggers rolling update
resource "aws_eks_node_group" "default" {
  # ...
  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }
}

resource "aws_launch_template" "nodes" {
  image_id = data.aws_ssm_parameter.eks_ami.value
  # ...
}
```

### I2. Schema Changes

See [Workstream E](#workstream-e--database--schema-management) for the Alembic migration workflow.

**Key demonstration points:**
1. Show the migration file (Python/SQL)
2. Explain that `ADD COLUMN ... DEFAULT` is non-blocking in PostgreSQL 11+
3. Show the Helm hook running the migration Job
4. Show the new code using the column
5. Show backward compatibility: old pods ignore new column, new pods use it

### I3. Chaos Testing Preparedness

**Scenarios to be ready for:**

| Scenario | Detection | Recovery |
|----------|-----------|----------|
| Pod killed | Grafana alert: pod restart count spike | K8s auto-restarts, HPA scales |
| Node failure | Grafana: node not ready alert | EKS replaces node, pods rescheduled |
| DB connection pool exhausted | Loki: connection timeout errors | Restart affected pods, check connection limits |
| Inference service OOM | Grafana: memory spike → pod eviction | K8s restarts with memory limit, check model size |
| High latency | Grafana: p99 latency > 5s | Check inference queue depth, scale workers |

**Runbook**: Each scenario has a Loki query + Grafana dashboard panel to diagnose:
```logql
# Find the failing service
{namespace="samosachaat-prod"} | json | level="error" | line_format "{{.service}}: {{.message}}"

# Check inference health
{app="inference"} | json | message=~".*error.*|.*timeout.*|.*OOM.*"
```

---

## Integration Contract & API Specs

### Service Communication Map

```
Frontend ──── HTTPS ────► ALB Ingress
                              │
                    ┌─────────┼──────────┐
                    ▼         ▼          ▼
               /api/auth  /api/chat  /api/models
                    │         │          │
                    ▼         ▼          ▼
              Auth Svc   Chat API    Chat API
              (8001)     (8002)      (8002)
                              │          │
                              ▼          ▼
                         Inference   Inference
                         (8003)      (8003)
                              │
                    ┌─────────┼──────────┐
                    ▼                    ▼
               PostgreSQL            EFS/Models
               (RDS)                 (weights)
```

### Shared Secrets (Kubernetes Secrets)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: samosachaat-secrets
data:
  DATABASE_URL: <base64>
  INTERNAL_API_KEY: <base64>
  JWT_PUBLIC_KEY: <base64>
  GOOGLE_CLIENT_ID: <base64>
  GOOGLE_CLIENT_SECRET: <base64>
  GITHUB_CLIENT_ID: <base64>
  GITHUB_CLIENT_SECRET: <base64>
  NEXTAUTH_SECRET: <base64>
```

---

## Execution Order & Dependency Graph

```
                    PHASE 1 (Parallel - No Dependencies)
    ┌──────────────────┬──────────────────┬──────────────────┐
    │   Workstream A   │   Workstream D   │   Workstream F   │
    │   Frontend UI    │   Inference Svc  │   Terraform IaC  │
    │   (Next.js)      │   (extract +     │   (VPC, EKS,     │
    │                  │    weight swap)   │    RDS, ECR)     │
    │   Uses mock API  │   Standalone     │   No code deps   │
    └────────┬─────────┴────────┬─────────┴────────┬─────────┘
             │                  │                   │
             │         PHASE 2 (Parallel - Needs DB schema)
    ┌────────┼─────────┬────────┼──────────────────┤
    │        │         │        │                   │
    │   Workstream B   │   Workstream C             │
    │   Auth Service   │   Chat API Svc             │
    │   (OAuth, JWT)   │   (Orchestration)          │
    │   Needs: DB      │   Needs: DB, Auth          │
    │                  │   contract, Inf contract    │
    └────────┬─────────┴────────┬───────────────────┘
             │                  │
             │         PHASE 3 (Sequential - Integration)
    ┌────────┴──────────────────┴───────────────────┐
    │              Workstream E                      │
    │   Database Migrations (Alembic)                │
    │   Needs: Auth + Chat API schemas finalized     │
    └───────────────────┬───────────────────────────┘
                        │
             ┌──────────┴──────────┐
    ┌────────┴─────────┐  ┌────────┴─────────┐
    │   Workstream G   │  │   Workstream H   │
    │   CI/CD Pipeline │  │   Observability  │
    │   Needs: ECR,    │  │   Needs: EKS     │
    │   EKS, Dockerf.  │  │   cluster        │
    └────────┬─────────┘  └────────┬─────────┘
             │                     │
             └──────────┬──────────┘
                        │
             ┌──────────┴──────────┐
             │   Workstream I      │
             │   Day 2 Operations  │
             │   (AMI patch, chaos)│
             │   Needs: Everything │
             └─────────────────────┘
```

### Agent Assignment Summary

| Agent | Workstreams | Can start immediately? | Deliverables |
|-------|-------------|----------------------|--------------|
| **Frontend Agent** | A | YES | Next.js app, Dockerfile, all components |
| **Backend Agent 1** | B, E | YES (against local PG) | Auth service, Alembic migrations |
| **Backend Agent 2** | C | YES (mock inference) | Chat API service, SSE proxy |
| **ML Agent** | D | YES | Inference service extracted from nanochat |
| **Infra Agent** | F, I | YES | Terraform modules, Day 2 scripts |
| **DevOps Agent** | G, H | After Phase 1 | GitHub Actions, Helm charts, Prometheus/Grafana/Loki |

### Local Development Quick Start

```bash
# Clone the new monorepo
git clone git@github.com:manmohan659/samosachaat.git
cd samosachaat

# Copy environment file
cp .env.example .env
# Edit .env with your Google/GitHub OAuth creds

# Start everything locally
docker compose up -d

# Services available at:
# Frontend:  http://localhost:3000
# Auth:      http://localhost:8001
# Chat API:  http://localhost:8002
# Inference: http://localhost:8003
# Grafana:   http://localhost:3001
# Postgres:  localhost:5432

# Run migrations
docker compose exec chat-api alembic upgrade head

# Seed test data
./scripts/seed-db.sh
```

### docker-compose.yml (Local Dev)

```yaml
version: '3.9'
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: samosachaat
      POSTGRES_USER: samosachaat_admin
      POSTGRES_PASSWORD: localdev
    ports: ['5432:5432']
    volumes:
      - pgdata:/var/lib/postgresql/data

  frontend:
    build: services/frontend
    ports: ['3000:3000']
    environment:
      - AUTH_SERVICE_URL=http://auth:8001
      - CHAT_API_URL=http://chat-api:8002
    depends_on: [auth, chat-api]

  auth:
    build: services/auth
    ports: ['8001:8001']
    environment:
      - DATABASE_URL=postgresql+asyncpg://samosachaat_admin:localdev@postgres:5432/samosachaat
    depends_on: [postgres]

  chat-api:
    build: services/chat-api
    ports: ['8002:8002']
    environment:
      - DATABASE_URL=postgresql+asyncpg://samosachaat_admin:localdev@postgres:5432/samosachaat
      - AUTH_SERVICE_URL=http://auth:8001
      - INFERENCE_SERVICE_URL=http://inference:8003
    depends_on: [postgres, auth, inference]

  inference:
    build: services/inference
    ports: ['8003:8003']
    environment:
      - MODEL_STORAGE_PATH=/models
      - DEFAULT_MODEL_TAG=samosachaat-d12
      - NANOCHAT_DTYPE=float32
    volumes:
      - ./models:/models

  grafana:
    image: grafana/grafana:latest
    ports: ['3001:3000']

  prometheus:
    image: prom/prometheus:latest
    ports: ['9090:9090']

  loki:
    image: grafana/loki:latest
    ports: ['3100:3100']

volumes:
  pgdata:
```

---

## Summary Checklist (Rubric Alignment)

| Rubric Category | Weight | How We Cover It |
|----------------|--------|-----------------|
| Infrastructure (Terraform) | 20% | Full Terraform modules: VPC, EKS, RDS, IAM, ECR, Route53, ACM. S3 state backend. Reusable module structure. Zero ClickOps. |
| Application & Networking | 15% | 4 microservices (frontend, auth, chat-api, inference). ALB Ingress with ACM SSL on `samosachaat.art`. Blue/Green zero-downtime rollout. |
| CI/CD & GitOps Logic | 15% | Dev→QA(nightly)→UAT(RC tags)→Prod(v* tags). Path-filtered builds. Conventional commits. Fully automated, no manual AWS console. |
| Day 2: OS Patching | 10% | EKS managed node group AMI rotation via Terraform. PDBs ensure zero downtime. Automated drain + replace. |
| Day 2: Schema Changes | 10% | Alembic migrations as Helm pre-upgrade hooks. Non-blocking DDL. Backward-compatible rollout demonstrated. |
| Observability & Logging | 15% | Self-hosted Prometheus + Grafana (OAuth2 only, no password) + Loki + Promtail. 3 dashboards. Email/Slack alerts. Multi-service log querying via Loki. |
| Presentation & Defense | 15% | Chaos readiness: Loki queries + Grafana dashboards for diagnosis. Runbook per failure scenario. |

---

*This plan is designed so each workstream section can be handed to an independent agent with full context to execute. Shared contracts (API specs, DB schema, env vars) are defined in the Integration Contract section. All agents should commit to the same monorepo on feature branches, merged via PR.*
