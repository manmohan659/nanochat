"""Database URL compatibility checks for hosted Postgres providers."""
from __future__ import annotations

import pytest

from src.database import _normalize_async_database_url


@pytest.mark.parametrize(
    ("input_url", "expected_url"),
    [
        (
            "postgresql://user:pass@host:5432/db",
            "postgresql+asyncpg://user:pass@host:5432/db",
        ),
        (
            "postgres://user:pass@host:5432/db",
            "postgresql+asyncpg://user:pass@host:5432/db",
        ),
        (
            "postgresql+asyncpg://user:pass@host:5432/db",
            "postgresql+asyncpg://user:pass@host:5432/db",
        ),
        ("sqlite+aiosqlite:///:memory:", "sqlite+aiosqlite:///:memory:"),
    ],
)
def test_normalize_async_database_url(input_url: str, expected_url: str) -> None:
    assert _normalize_async_database_url(input_url) == expected_url
