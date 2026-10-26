from types import SimpleNamespace
import pytest
from src.services.google_oauth import profile_from_userinfo
from src.services.github_oauth import profile_from_userinfo as github_profile
from src.tests.test_oauth_flow import _MockGoogleClient

@pytest.mark.parametrize("verified", [False, None, "true", 1])
def test_google_requires_true_verified_email(verified):
    with pytest.raises(ValueError):
        profile_from_userinfo({"sub": "subject", "email": "test@example.invalid", "email_verified": verified})

def test_github_does_not_trust_public_profile_email():
    with pytest.raises(ValueError):
        github_profile({"id": 1, "email": "test@example.invalid"}, [])
    profile = github_profile({"id": 1, "email": "wrong@example.invalid"}, [{"email": "verified@example.invalid", "primary": True, "verified": True}])
    assert profile.email == "verified@example.invalid"

@pytest.mark.asyncio
async def test_callback_rejects_unverified_identity(client):
    client._transport.app.state.google_oauth = SimpleNamespace(google=_MockGoogleClient({"sub": "bad", "email": "test@example.invalid", "email_verified": False}))
    response = await client.get("/auth/google/callback")
    assert response.status_code == 400
    assert "Unable to link" in response.json()["detail"]

@pytest.mark.asyncio
async def test_private_metrics_and_no_public_schema(client):
    assert (await client.get("/metrics")).status_code == 404
    assert (await client.get("/metrics", headers={"X-Internal-API-Key": "test-internal-key"})).status_code == 200
    assert (await client.get("/openapi.json")).status_code == 404
    response = await client.get("/auth/health")
    assert response.status_code == 200
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.headers["cache-control"] == "no-store"
