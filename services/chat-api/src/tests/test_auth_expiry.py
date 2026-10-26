import pytest
from src.middleware.auth_guard import AuthCache, AuthenticatedUser

@pytest.mark.asyncio
async def test_cache_never_extends_signed_expiry(monkeypatch):
    monkeypatch.setattr("src.middleware.auth_guard.time.time", lambda: 1000)
    cache = AuthCache(ttl_seconds=300, max_size=10)
    user = AuthenticatedUser.from_validate_response({"user": {"id": "synthetic"}, "claims": {"exp": 1001}})
    await cache.set("synthetic-token", user)
    assert await cache.get("synthetic-token") is user
    monkeypatch.setattr("src.middleware.auth_guard.time.time", lambda: 1001)
    assert await cache.get("synthetic-token") is None

@pytest.mark.asyncio
async def test_cache_does_not_cache_missing_expiry():
    cache = AuthCache(ttl_seconds=300, max_size=10)
    user = AuthenticatedUser.from_validate_response({"user": {"id": "synthetic"}})
    await cache.set("synthetic-token", user)
    assert await cache.get("synthetic-token") is None
