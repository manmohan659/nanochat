# samosaChaat Logging Standard

All services in the samosaChaat platform emit logs as **single-line JSON**
on stdout. Promtail ships them to Loki, where Grafana queries them by label
and by JSON field. Because every service shares the same schema, a single
trace_id plus session_trace_id let you follow a request from the frontend
through auth → chat-api → inference.

## Required fields

Every log line MUST include:

| Field       | Type    | Source                                   |
|-------------|---------|------------------------------------------|
| `timestamp` | ISO8601 | structlog `TimeStamper(fmt="iso")`       |
| `level`     | string  | `debug` / `info` / `warning` / `error`   |
| `service`   | string  | hard-coded per service (`auth`, `chat-api`, `inference`, `frontend`) |
| `message`   | string  | the human-readable event (`event` key in structlog) |

Conditionally included (when present in the request context):

| Field        | When to include                          |
|--------------|------------------------------------------|
| `trace_id`   | every request served by a backend service — propagated via the `x-trace-id` header |
| `session_trace_id` | browser-session correlation — propagated via the `x-session-trace-id` header |
| `user_id`    | every request authenticated as a user    |
| `inference_time_ms` | emitted by chat-api and inference around model calls |
| `error`      | on exceptions — the stringified cause    |

Anything else is free-form structured context (`method`, `path`,
`status_code`, `model_tag`, …). Keep keys `snake_case`.

## Python implementation — `structlog`

The canonical setup lives at `services/chat-api/src/logging_setup.py`.
`services/auth/src/logging_setup.py` and `services/inference/src/logging_setup.py`
mirror it, differing only in the hard-coded `service` value.

Key pieces:

```python
structlog.configure(
    processors=[
        structlog.contextvars.merge_contextvars,   # trace_id / session_trace_id / user_id
        structlog.processors.add_log_level,        # -> level field
        structlog.processors.TimeStamper(fmt="iso", utc=True),
        _inject_context,                           # service + request context defaults
        structlog.processors.JSONRenderer(),       # final JSON line
    ],
    ...
)
```

Each service calls `configure_logging()` once at startup (inside
`create_app()`), and then uses `logger = get_logger(__name__)` everywhere.
`trace_id` is set by a FastAPI middleware that reads the incoming
`x-trace-id` header (or mints a new one via `new_trace_id()`). The same
middleware binds `session_trace_id` from `x-session-trace-id` when present.
Both values are propagated to downstream calls.

Container entrypoints run Uvicorn with `--no-access-log`; request logs must come
from the JSON middleware events rather than plaintext Uvicorn access lines.

## Node.js implementation — `pino` (frontend)

The Next.js frontend should log JSON with the same schema. Reference config:

```ts
// services/frontend/lib/logger.ts
import pino from "pino";

export const logger = pino({
  base: { service: "frontend" },
  timestamp: () => `,"timestamp":"${new Date().toISOString()}"`,
  formatters: {
    level: (label) => ({ level: label }),   // keep the string level
  },
  messageKey: "message",
});
```

When emitting, always include `trace_id`, `session_trace_id`, and `user_id`
when known:

```ts
logger.info({ trace_id, session_trace_id, user_id, path: req.url }, "request_start");
```

In API routes, read the incoming `x-trace-id` header and echo it back on the
response so client-side traces can join up.

## Cross-service querying (LogQL / Grafana Explore)

Labels Promtail applies: `namespace`, `app`, `pod`, `level`, `service`,
`container`. Everything else is a JSON field — use `| json` to extract it.

| Goal                          | Query                                                                 |
|-------------------------------|-----------------------------------------------------------------------|
| All errors in prod            | `{namespace="samosachaat-prod"} | json | level="error"`               |
| Trace a request across tiers  | `{namespace="samosachaat-prod"} | json | trace_id="<trace>"`          |
| Trace a browser session       | `{namespace="samosachaat-prod"} | json | session_trace_id="<session>"` |
| Trace a user                  | `{namespace="samosachaat-prod"} | json | user_id="<user-id>"`          |
| Auth failures                 | `{namespace="samosachaat-prod"} | json | service="auth" | level="error"`         |
| Slow inference calls          | `{namespace="samosachaat-prod"} | json | service="inference" | inference_time_ms > 5000` |
| 5xx by service                | `{namespace="samosachaat-prod"} | json | status_code >= 500`          |
| Rate-limited OAuth logins     | `{namespace="samosachaat-prod"} | json | service="auth" | path=~"/auth/oauth/.*" | status_code=429` |

## Trace propagation contract

1. **Frontend** — mint `x-session-trace-id` once per browser session and send it
   on every `fetch` to the API. Frontend API routes also mint or forward
   `x-trace-id` for per-request correlation.
2. **chat-api** — read `x-trace-id` and `x-session-trace-id`, store them in
   context vars, re-emit them on the response, and forward them on every httpx
   call to auth or inference. It forwards `x-user-id` to inference only from the
   validated JWT user context.
3. **auth / inference** — read `x-trace-id` and `x-session-trace-id` and bind
   them to the logger context for the duration of the request. Authenticated
   auth routes and inference calls bind `user_id` only after auth/internal
   validation succeeds.

Services MUST NOT log raw secrets, JWTs, OAuth client secrets, API keys, or
full user message text. Log IDs, lengths, and booleans — not contents.
