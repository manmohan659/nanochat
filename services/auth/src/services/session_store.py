"""Atomic one-time exchange and durable refresh rotation; never store raw tokens."""
from __future__ import annotations
import base64
import hashlib
import secrets
import time
import uuid
from sqlalchemy import update, select
from sqlalchemy.ext.asyncio import AsyncSession
from ..models.session import LoginCode, RefreshCredential, RefreshFamily
from .jwt_service import JWTService, TokenPair, JWTError
from .user_service import get_by_id

class SessionRejected(Exception):
    pass

def digest(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()

def pkce_challenge(verifier: str) -> str:
    return base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()

async def issue_code(session: AsyncSession, user_id: uuid.UUID, challenge: str) -> str:
    code = secrets.token_urlsafe(32)
    session.add(LoginCode(digest=digest(code), user_id=user_id, challenge=challenge, expires_at=int(time.time())+60, consumed=False))
    await session.commit()
    return code

async def _pair(session: AsyncSession, user, family: str) -> TokenPair:
    jwt = JWTService()
    pair = jwt.issue_pair(user_id=str(user.id), email=user.email, name=user.name)
    session.add(RefreshCredential(digest=digest(pair.refresh_token), user_id=user.id, family=family, expires_at=int(time.time())+pair.refresh_expires_in, consumed=False, revoked=False))
    return pair

async def exchange(session: AsyncSession, code: str, verifier: str) -> TokenPair:
    result = await session.execute(update(LoginCode).where(LoginCode.digest == digest(code), LoginCode.challenge == pkce_challenge(verifier), LoginCode.expires_at > int(time.time()), LoginCode.consumed.is_(False)).values(consumed=True).returning(LoginCode.user_id))
    user_id = result.scalar_one_or_none()
    if user_id is None:
        await session.rollback()
        raise SessionRejected()
    user = await get_by_id(session, user_id)
    if user is None:
        await session.rollback()
        raise SessionRejected()
    family = uuid.uuid4().hex
    session.add(RefreshFamily(id=family, revoked=False))
    await session.flush()
    pair = await _pair(session, user, family)
    await session.commit()
    return pair

async def rotate(session: AsyncSession, token: str) -> TokenPair:
    try:
        claims = JWTService().decode(token, expected_type="refresh")
    except JWTError:
        raise SessionRejected() from None
    credential = await session.get(RefreshCredential, digest(token))
    if credential is None:
        await session.rollback()
        raise SessionRejected()
    # Every family mutation takes this stable row lock before inspecting/consuming a token.
    # This fences a successor insert against concurrent old-token replay/logout revocation.
    family = (await session.execute(select(RefreshFamily).where(RefreshFamily.id == credential.family).with_for_update().execution_options(populate_existing=True))).scalar_one()
    if family.revoked:
        await session.rollback()
        raise SessionRejected()
    result = await session.execute(update(RefreshCredential).where(RefreshCredential.digest == digest(token), RefreshCredential.expires_at > int(time.time()), RefreshCredential.consumed.is_(False), RefreshCredential.revoked.is_(False)).values(consumed=True).returning(RefreshCredential.user_id, RefreshCredential.family))
    row = result.first()
    if row is None:
        family.revoked = True
        await session.commit()
        raise SessionRejected()
    user = await get_by_id(session, row.user_id)
    if user is None or str(user.id) != claims["sub"]:
        await session.rollback()
        raise SessionRejected()
    pair = await _pair(session, user, row.family)
    await session.commit()
    return pair

async def revoke(session: AsyncSession, token: str) -> None:
    credential = await session.get(RefreshCredential, digest(token))
    if credential is not None:
        family = (await session.execute(select(RefreshFamily).where(RefreshFamily.id == credential.family).with_for_update().execution_options(populate_existing=True))).scalar_one()
        family.revoked = True
        await session.commit()
