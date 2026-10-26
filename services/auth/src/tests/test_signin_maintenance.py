import pytest
from httpx import ASGITransport, AsyncClient

@pytest.mark.asyncio
async def test_maintenance_blocks_new_signin_and_callback_without_provider_calls(monkeypatch, session_factory):
    from src.config import get_settings
    monkeypatch.setenv("SIGNIN_MAINTENANCE", "true")
    get_settings.cache_clear()
    try:
        from src.main import create_app
        app = create_app()
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            for path in ["/auth/google", "/auth/github", "/auth/google/callback", "/auth/github/callback"]:
                response = await client.get(path, params={"code": "synthetic-sensitive-marker"})
                assert response.status_code == 503
                assert response.headers["retry-after"] == "60"
                assert "synthetic-sensitive-marker" not in response.text
                assert "location" not in response.headers
            assert (await client.get("/auth/health")).status_code == 200
            assert (await client.get("/auth/me")).status_code == 401
        assert not hasattr(app.state, "google_oauth")
        assert not hasattr(app.state, "github_oauth")
    finally:
        get_settings.cache_clear()
