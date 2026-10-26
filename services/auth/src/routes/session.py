"""Session/token refresh routes + internal JWT validation."""
import secrets

from fastapi import APIRouter, Depends, Header, HTTPException, Request, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import get_settings
from ..database import get_session
from ..logging_setup import set_user_id
from ..rate_limit import limiter
from ..services import user_service, session_store
from ..services.jwt_service import JWTError, JWTService

router = APIRouter(prefix="/auth", tags=["session"])


class ExchangeRequest(BaseModel):
    code: str = Field(min_length=40, max_length=128)
    verifier: str = Field(min_length=43, max_length=128, pattern=r"^[A-Za-z0-9_-]+$")

class RefreshRequest(BaseModel):
    token: str = Field(min_length=1, max_length=8192)

class ValidateRequest(BaseModel):
    token: str

def require_internal(x_internal_api_key: str | None = Header(default=None, alias="X-Internal-API-Key")):
    expected = get_settings().internal_api_key
    if not expected or not secrets.compare_digest(x_internal_api_key or "", expected):
        raise HTTPException(403, "invalid internal api key")

@router.post("/exchange", dependencies=[Depends(require_internal)])
@limiter.limit("30/minute")
async def exchange(request: Request, payload: ExchangeRequest, session: AsyncSession = Depends(get_session)):
    try:
        return await session_store.exchange(session, payload.code, payload.verifier)
    except session_store.SessionRejected:
        raise HTTPException(401, "Login expired; restart sign-in") from None

@router.post("/refresh", dependencies=[Depends(require_internal)])
@limiter.limit("30/minute")
async def refresh(request: Request, payload: RefreshRequest, session: AsyncSession = Depends(get_session)):
    try:
        return await session_store.rotate(session, payload.token)
    except session_store.SessionRejected:
        raise HTTPException(401, "Session expired; sign in again") from None

@router.post("/logout", dependencies=[Depends(require_internal)])
async def logout(payload: RefreshRequest, session: AsyncSession = Depends(get_session)):
    await session_store.revoke(session, payload.token)
    return {"ok": True}


@router.post("/validate")
async def validate(
    request: Request,
    payload: ValidateRequest,
    session: AsyncSession = Depends(get_session),
    x_internal_api_key: str | None = Header(default=None, alias="X-Internal-API-Key"),
):
    settings = get_settings()
    if not settings.internal_api_key or not secrets.compare_digest(x_internal_api_key or "", settings.internal_api_key):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "invalid internal api key")

    jwt_service = JWTService()
    try:
        claims = jwt_service.decode(payload.token, expected_type="access")
    except JWTError as exc:
        return JSONResponse(
            status_code=status.HTTP_401_UNAUTHORIZED,
            content={"valid": False, "reason": str(exc)},
        )

    user = await user_service.get_by_id(session, claims["sub"])
    if user is None:
        return JSONResponse(
            status_code=status.HTTP_401_UNAUTHORIZED,
            content={"valid": False, "reason": "user not found"},
        )
    set_user_id(str(user.id))
    request.state.user_id = str(user.id)

    return {"valid": True, "user": user.to_dict(), "claims": claims}
