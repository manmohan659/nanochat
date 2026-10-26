import time
from urllib.parse import urlparse, parse_qs
from types import SimpleNamespace
import pytest
from sqlalchemy import select
from src.services import user_service, session_store
from src.services.google_oauth import OAuthProfile
from src.models.session import LoginCode, RefreshCredential
from src.tests.test_oauth_flow import _MockGoogleClient
HEADERS = {"X-Internal-API-Key": "test-internal-key"}
VERIFIER = "v" * 43
async def login_code(db_session):
    user = await user_service.upsert_from_oauth(db_session, OAuthProfile("google", "session-user", "session@example.invalid", "Session", None))
    return await session_store.issue_code(db_session, user.id, session_store.pkce_challenge(VERIFIER))
@pytest.mark.asyncio
async def test_pkce_code_is_one_time_and_not_a_bearer(client, db_session):
    code = await login_code(db_session)
    payload = {"code": code, "verifier": VERIFIER}
    assert (await client.post("/auth/exchange", json=payload)).status_code == 403
    wrong = await client.post("/auth/exchange", json={**payload, "verifier": "x"*43}, headers=HEADERS)
    assert wrong.status_code == 401, wrong.text
    response = await client.post("/auth/exchange", json=payload, headers=HEADERS)
    assert response.status_code == 200, response.text
    assert (await client.post("/auth/exchange", json=payload, headers=HEADERS)).status_code == 401
    rows = (await db_session.execute(select(RefreshCredential))).scalars().all()
    assert len(rows) == 1
    assert rows[0].digest != response.json()["refresh_token"]
@pytest.mark.asyncio
async def test_expired_code_rejected(client, db_session):
    code = await login_code(db_session)
    row = await db_session.get(LoginCode, session_store.digest(code))
    row.expires_at = int(time.time())-1
    await db_session.commit()
    assert (await client.post("/auth/exchange", json={"code": code, "verifier": VERIFIER}, headers=HEADERS)).status_code == 401
@pytest.mark.asyncio
async def test_refresh_rotation_replay_revokes_replacement(client, db_session):
    pair = await session_store.exchange(db_session, await login_code(db_session), VERIFIER)
    response = await client.post("/auth/refresh", json={"token": pair.refresh_token}, headers=HEADERS)
    assert response.status_code == 200, response.text
    next_token = response.json()["refresh_token"]
    assert next_token != pair.refresh_token
    assert (await client.post("/auth/refresh", json={"token": pair.refresh_token}, headers=HEADERS)).status_code == 401
    assert (await client.post("/auth/refresh", json={"token": next_token}, headers=HEADERS)).status_code == 401
@pytest.mark.asyncio
async def test_logout_revokes_refresh(client, db_session):
    pair = await session_store.exchange(db_session, await login_code(db_session), VERIFIER)
    assert (await client.post("/auth/logout", json={"token": pair.refresh_token}, headers=HEADERS)).status_code == 200
    assert (await client.post("/auth/refresh", json={"token": pair.refresh_token}, headers=HEADERS)).status_code == 401
@pytest.mark.asyncio
async def test_login_requires_frontend_pkce_challenge(client):
    assert (await client.get("/auth/google")).status_code == 400
@pytest.mark.asyncio
async def test_oauth_callback_exchange_integration(client):
    client._transport.app.state.google_oauth = SimpleNamespace(google=_MockGoogleClient({"sub":"integration", "email":"flow@example.invalid", "email_verified":True}))
    assert (await client.get("/auth/google", params={"code_challenge":session_store.pkce_challenge(VERIFIER)})).status_code in (302,307)
    callback = await client.get("/auth/google/callback")
    assert callback.status_code == 302
    code = parse_qs(urlparse(callback.headers["location"]).query)["code"][0]
    pair = await client.post("/auth/exchange", json={"code":code,"verifier":VERIFIER}, headers=HEADERS)
    assert pair.status_code == 200
    valid = await client.post("/auth/validate", json={"token":pair.json()["access_token"]}, headers=HEADERS)
    assert valid.status_code == 200 and valid.json()["valid"] is True
