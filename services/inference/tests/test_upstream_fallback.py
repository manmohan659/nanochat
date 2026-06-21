from fastapi import HTTPException, status
from fastapi.testclient import TestClient

import main
from config import Settings


class NoModelRuntime:
    async def startup(self):
        return None

    async def shutdown(self):
        return None

    def require_ready_pool(self):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="No model is currently loaded",
        )

    def models_payload(self):
        return {"current_model": None, "models": []}

    def health_payload(self):
        return {"status": "ok", "ready": False}

    def stats_payload(self):
        return {"current_model": None}


class FakeUpstreamResponse:
    status_code = 200

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, tb):
        return None

    async def aiter_text(self):
        yield 'data: {"token":"ok"}\n\n'
        yield 'data: {"done":true}\n\n'


class FakeAsyncClient:
    captured_json = None

    def __init__(self, *args, **kwargs):
        pass

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, tb):
        return None

    def stream(self, method, url, *, headers, json):
        self.__class__.captured_json = json
        return FakeUpstreamResponse()


class FailingAsyncClient:
    def __init__(self, *args, **kwargs):
        pass

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, tb):
        return None

    def stream(self, method, url, *, headers, json):
        raise TimeoutError("upstream timed out")


class FailingStatusResponse:
    status_code = 404

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, tb):
        return None

    async def aread(self):
        return b'{"detail":"Not Found"}'


class FailingStatusAsyncClient:
    def __init__(self, *args, **kwargs):
        pass

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, tb):
        return None

    def stream(self, method, url, *, headers, json):
        return FailingStatusResponse()


class UnexpectedAsyncClient:
    def __init__(self, *args, **kwargs):
        pass

    async def __aenter__(self):
        raise AssertionError("self-referential upstream should not be called")

    async def __aexit__(self, exc_type, exc, tb):
        return None


def test_generate_proxies_to_upstream_when_local_model_missing(monkeypatch):
    monkeypatch.setattr(main.httpx, "AsyncClient", FakeAsyncClient)
    settings = Settings(
        internal_api_key="test-key",
        startup_load_enabled=False,
        upstream_generate_url="https://example.test/generate",
    )
    app = main.create_app(settings=settings, runtime=NoModelRuntime())

    with TestClient(app) as client:
        response = client.post(
            "/generate",
            headers={"X-Internal-API-Key": "test-key"},
            json={
                "messages": [{"role": "user", "content": "hello"}],
                "max_tokens": 4,
                "force_web_search": True,
            },
        )

    assert response.status_code == 200
    assert 'data: {"token":"ok"}' in response.text
    assert FakeAsyncClient.captured_json == {
        "messages": [{"role": "user", "content": "hello"}],
        "max_tokens": 4,
        "force_web_search": True,
    }


def test_generate_uses_demo_fallback_when_upstream_fails(monkeypatch):
    monkeypatch.setattr(main.httpx, "AsyncClient", FailingAsyncClient)
    settings = Settings(
        internal_api_key="test-key",
        startup_load_enabled=False,
        upstream_generate_url="https://example.test/generate",
        demo_fallback_enabled=True,
    )
    app = main.create_app(settings=settings, runtime=NoModelRuntime())

    with TestClient(app) as client:
        response = client.post(
            "/generate",
            headers={"X-Internal-API-Key": "test-key"},
            json={"messages": [{"role": "user", "content": "hello"}]},
        )

    assert response.status_code == 200
    assert '"gpu":"fallback"' in response.text
    assert '"token":"demo "' in response.text
    assert '"token":"fallback "' in response.text
    assert 'data: {"done":true}' in response.text


def test_generate_uses_demo_fallback_when_upstream_returns_error(monkeypatch):
    monkeypatch.setattr(main.httpx, "AsyncClient", FailingStatusAsyncClient)
    settings = Settings(
        internal_api_key="test-key",
        startup_load_enabled=False,
        upstream_generate_url="https://example.test/generate",
        demo_fallback_enabled=True,
    )
    app = main.create_app(settings=settings, runtime=NoModelRuntime())

    with TestClient(app) as client:
        response = client.post(
            "/generate",
            headers={"X-Internal-API-Key": "test-key"},
            json={"messages": [{"role": "user", "content": "hello"}]},
        )

    assert response.status_code == 200
    assert '"gpu":"fallback"' in response.text
    assert '"token":"demo "' in response.text
    assert 'data: {"done":true}' in response.text


def test_generate_uses_demo_fallback_without_upstream():
    settings = Settings(
        internal_api_key="test-key",
        startup_load_enabled=False,
        demo_fallback_enabled=True,
    )
    app = main.create_app(settings=settings, runtime=NoModelRuntime())

    with TestClient(app) as client:
        response = client.post(
            "/generate",
            headers={"X-Internal-API-Key": "test-key"},
            json={"messages": [{"role": "user", "content": "hello"}]},
        )

    assert response.status_code == 200
    assert '"gpu":"fallback"' in response.text
    assert '"token":"demo "' in response.text
    assert 'data: {"done":true}' in response.text


def test_generate_uses_demo_fallback_for_self_referential_upstream(monkeypatch):
    monkeypatch.setattr(main.httpx, "AsyncClient", UnexpectedAsyncClient)
    settings = Settings(
        internal_api_key="test-key",
        startup_load_enabled=False,
        upstream_generate_url="http://inference:8003",
        demo_fallback_enabled=True,
    )
    app = main.create_app(settings=settings, runtime=NoModelRuntime())

    with TestClient(app) as client:
        response = client.post(
            "/generate",
            headers={"X-Internal-API-Key": "test-key"},
            json={"messages": [{"role": "user", "content": "hello"}]},
        )

    assert response.status_code == 200
    assert '"gpu":"fallback"' in response.text
    assert '"token":"demo "' in response.text
    assert 'data: {"done":true}' in response.text
