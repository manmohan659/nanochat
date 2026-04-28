"""Admin-only routes. Gated on ADMIN_EMAIL match against the JWT user."""
from __future__ import annotations

from typing import Annotated

import sqlalchemy as sa
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import Settings, get_settings
from ..database import get_session
from ..middleware.auth_guard import AuthenticatedUser, require_user

router = APIRouter(prefix="/api/admin", tags=["admin"])


def _require_admin(
    user: AuthenticatedUser,
    settings: Settings,
) -> None:
    if not user.email or user.email.lower() != settings.admin_email.lower():
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="admin only")


@router.get("/users")
async def list_users(
    user: Annotated[AuthenticatedUser, Depends(require_user)],
    session: Annotated[AsyncSession, Depends(get_session)],
    settings: Annotated[Settings, Depends(get_settings)],
):
    _require_admin(user, settings)

    stmt = sa.text(
        """
        SELECT
            u.id::text          AS id,
            u.email             AS email,
            u.name              AS name,
            u.provider          AS provider,
            u.created_at        AS created_at,
            u.last_login_at     AS last_login_at,
            COUNT(DISTINCT c.id) AS conversation_count,
            COUNT(m.id)          AS message_count
        FROM users u
        LEFT JOIN conversations c ON c.user_id = u.id
        LEFT JOIN messages m       ON m.conversation_id = c.id
        GROUP BY u.id
        ORDER BY u.last_login_at DESC NULLS LAST
        """
    )
    rows = (await session.execute(stmt)).mappings().all()

    items = [
        {
            "id": r["id"],
            "email": r["email"],
            "name": r["name"],
            "provider": r["provider"],
            "created_at": r["created_at"].isoformat() if r["created_at"] else None,
            "last_login_at": r["last_login_at"].isoformat() if r["last_login_at"] else None,
            "conversation_count": int(r["conversation_count"] or 0),
            "message_count": int(r["message_count"] or 0),
        }
        for r in rows
    ]

    totals = {
        "users": len(items),
        "conversations": sum(it["conversation_count"] for it in items),
        "messages": sum(it["message_count"] for it in items),
    }

    return {"items": items, "totals": totals}
