"""OAuth start/callback routes for Google and GitHub."""
from __future__ import annotations
import re
from urllib.parse import urlencode

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import RedirectResponse
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import get_settings
from ..database import get_session
from ..logging_setup import set_user_id
from ..rate_limit import limiter
from ..services import github_oauth as github_provider
from ..services import google_oauth as google_provider
from ..services import user_service, session_store

router = APIRouter(prefix="/auth", tags=["oauth"])


def _save_challenge(request: Request) -> None:
    challenge = request.query_params.get("code_challenge", "")
    if not re.fullmatch(r"[A-Za-z0-9_-]{43}", challenge):
        raise HTTPException(400, "Restart sign-in from the application")
    request.session["login_challenge"] = challenge

async def _finish_login(request: Request, session: AsyncSession, user):
    challenge = request.session.pop("login_challenge", None)
    if not challenge:
        raise HTTPException(400, "Restart sign-in from the application")
    code = await session_store.issue_code(session, user.id, challenge)
    settings = get_settings()
    return RedirectResponse(f"{settings.frontend_url.rstrip('/')}/chat?{urlencode({'code': code})}", status_code=302)


def _google_oauth(request: Request):
    client = getattr(request.app.state, "google_oauth", None)
    if client is None:
        client = google_provider.build_google_client()
        request.app.state.google_oauth = client
    return client.google


def _github_oauth(request: Request):
    client = getattr(request.app.state, "github_oauth", None)
    if client is None:
        client = github_provider.build_github_client()
        request.app.state.github_oauth = client
    return client.github


@router.get("/google")
@limiter.limit("10/minute")
async def google_start(request: Request):
    _save_challenge(request)
    settings = get_settings()
    redirect_uri = f"{settings.auth_base_url.rstrip('/')}/auth/google/callback"
    return await _google_oauth(request).authorize_redirect(request, redirect_uri)


@router.get("/google/callback")
@limiter.limit("10/minute")
async def google_callback(
    request: Request,
    session: AsyncSession = Depends(get_session),
):
    oauth = _google_oauth(request)
    try:
        token = await oauth.authorize_access_token(request)
    except Exception as exc:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "google oauth failed") from exc

    userinfo = token.get("userinfo")
    if not userinfo:
        userinfo = await oauth.userinfo(token=token)

    try:
        profile = google_provider.profile_from_userinfo(dict(userinfo))
        user = await user_service.upsert_from_oauth(session, profile)
    except ValueError as exc:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Unable to link OAuth identity") from exc
    set_user_id(str(user.id))

    return await _finish_login(request, session, user)


@router.get("/github")
@limiter.limit("10/minute")
async def github_start(request: Request):
    _save_challenge(request)
    settings = get_settings()
    redirect_uri = f"{settings.auth_base_url.rstrip('/')}/auth/github/callback"
    return await _github_oauth(request).authorize_redirect(request, redirect_uri)


@router.get("/github/callback")
@limiter.limit("10/minute")
async def github_callback(
    request: Request,
    session: AsyncSession = Depends(get_session),
):
    oauth = _github_oauth(request)
    try:
        token = await oauth.authorize_access_token(request)
    except Exception as exc:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "github oauth failed") from exc

    user_resp = await oauth.get("user", token=token)
    user_resp.raise_for_status()
    userinfo = user_resp.json()

    emails: list[dict] | None = None
    emails_resp = await oauth.get("user/emails", token=token)
    if emails_resp.status_code == 200:
        emails = emails_resp.json()

    try:
        profile = github_provider.profile_from_userinfo(dict(userinfo), emails)
        user = await user_service.upsert_from_oauth(session, profile)
    except ValueError as exc:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Unable to link OAuth identity") from exc
    set_user_id(str(user.id))

    return await _finish_login(request, session, user)
