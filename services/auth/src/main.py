"""FastAPI entrypoint for the samosaChaat auth service."""
from __future__ import annotations

from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from prometheus_fastapi_instrumentator import Instrumentator
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
from starlette.middleware.sessions import SessionMiddleware

from .config import get_settings
from .logging_setup import (
    configure_logging,
    get_logger,
    new_trace_id,
    set_session_trace_id,
    set_trace_id,
    set_user_id,
)
from .rate_limit import limiter
from .routes import oauth, session, users


def _rate_limit_handler(request, exc: RateLimitExceeded):
    return JSONResponse(status_code=429, content={"detail": "rate limit exceeded"})


def create_app() -> FastAPI:
    configure_logging()
    settings = get_settings()
    logger = get_logger(__name__)
    app = FastAPI(title="samosaChaat Auth", version="0.1.0")

    app.state.limiter = limiter
    app.add_exception_handler(RateLimitExceeded, _rate_limit_handler)
    app.add_middleware(SlowAPIMiddleware)

    # SessionMiddleware is required by authlib for the OAuth state cookie.
    app.add_middleware(SessionMiddleware, secret_key=settings.session_secret)

    app.add_middleware(
        CORSMiddleware,
        allow_origins=[settings.frontend_url],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.middleware("http")
    async def request_context(request: Request, call_next) -> Response:
        incoming = request.headers.get("x-trace-id") or request.headers.get("x-request-id")
        trace_id = incoming or new_trace_id()
        session_trace_id = request.headers.get("x-session-trace-id")
        set_trace_id(trace_id)
        set_session_trace_id(session_trace_id)
        set_user_id(None)

        logger.info("request_start", method=request.method, path=request.url.path)
        try:
            response = await call_next(request)
        except Exception:
            logger.exception("request_failed", method=request.method, path=request.url.path)
            raise
        response.headers["x-trace-id"] = trace_id
        if session_trace_id:
            response.headers["x-session-trace-id"] = session_trace_id
        user_id = getattr(request.state, "user_id", None)
        auth_ctx = getattr(request.state, "auth", None)
        if user_id is None and auth_ctx is not None:
            user_id = getattr(getattr(auth_ctx, "user", None), "id", None)
        if user_id is not None:
            set_user_id(str(user_id))
        logger.info(
            "request_end",
            method=request.method,
            path=request.url.path,
            status_code=response.status_code,
        )
        return response

    app.include_router(oauth.router)
    app.include_router(session.router)
    app.include_router(users.router)

    @app.get("/auth/health")
    async def health():
        return {"status": "ok"}

    Instrumentator().instrument(app).expose(app, endpoint="/metrics", include_in_schema=False)

    return app


app = create_app()
