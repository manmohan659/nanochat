"""Hashed one-time login codes and rotating refresh credentials."""
from __future__ import annotations
import uuid
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column
from ..database import Base

class LoginCode(Base):
    __tablename__ = "auth_login_codes"
    digest: Mapped[str] = mapped_column(sa.String(64), primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(sa.Uuid(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    challenge: Mapped[str] = mapped_column(sa.String(43), nullable=False)
    expires_at: Mapped[int] = mapped_column(sa.BigInteger(), nullable=False)
    consumed: Mapped[bool] = mapped_column(sa.Boolean(), default=False, nullable=False)

class RefreshFamily(Base):
    __tablename__ = "auth_refresh_families"
    id: Mapped[str] = mapped_column(sa.String(32), primary_key=True)
    revoked: Mapped[bool] = mapped_column(sa.Boolean(), default=False, nullable=False)

class RefreshCredential(Base):
    __tablename__ = "auth_refresh_credentials"
    digest: Mapped[str] = mapped_column(sa.String(64), primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(sa.Uuid(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    family: Mapped[str] = mapped_column(sa.String(32), sa.ForeignKey("auth_refresh_families.id", ondelete="CASCADE"), index=True, nullable=False)
    expires_at: Mapped[int] = mapped_column(sa.BigInteger(), nullable=False)
    consumed: Mapped[bool] = mapped_column(sa.Boolean(), default=False, nullable=False)
    revoked: Mapped[bool] = mapped_column(sa.Boolean(), default=False, nullable=False)
