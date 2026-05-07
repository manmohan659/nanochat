"""Tests for the streaming message send + regenerate flows."""
from __future__ import annotations

import json
import uuid

import httpx
import pytest
import respx

from .conftest import stub_auth_validate


def _build_inference_mock(tokens: list[str]) -> httpx.MockTransport:
    """Build an httpx mock transport that streams an SSE response."""
    sse_lines: list[bytes] = []
    for token in tokens:
        sse_lines.append(
            f"data: {json.dumps({'token': token, 'gpu': 0})}\n\n".encode("utf-8")
        )
    sse_lines.append(f"data: {json.dumps({'done': True})}\n\n".encode("utf-8"))

    async def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path != "/generate":
            return httpx.Response(404)

        async def body():
            for chunk in sse_lines:
                yield chunk

        return httpx.Response(
            200,
            headers={"content-type": "text/event-stream"},
            content=body(),
        )

    return httpx.MockTransport(handler)


@pytest.mark.asyncio
@respx.mock
async def test_send_message_streams_and_persists(app, client, seeded_user):
    stub_auth_validate(respx.mock, seeded_user)
    headers = {"Authorization": "Bearer valid-token"}

    create = await client.post("/api/conversations", json={}, headers=headers)
    convo_id = create.json()["id"]

    app.state.inference_http_client = httpx.AsyncClient(
        transport=_build_inference_mock(["hel", "lo", " world"])
    )
    try:
        resp = await client.post(
            f"/api/conversations/{convo_id}/messages",
            json={"content": "hi there"},
            headers=headers,
        )
        assert resp.status_code == 200
        body = resp.text
        assert '"token": "hel"' in body or '"token":"hel"' in body
        assert '"done": true' in body or '"done":true' in body
    finally:
        await app.state.inference_http_client.aclose()

    fetched = await client.get(
        f"/api/conversations/{convo_id}", headers=headers
    )
    assert fetched.status_code == 200
    payload = fetched.json()
    messages = payload["messages"]

    roles = [m["role"] for m in messages]
    assert roles == ["user", "assistant"]
    assert messages[0]["content"] == "hi there"
    assert messages[1]["content"] == "hello world"
    assert messages[1]["token_count"] == 3
    assert messages[1]["inference_time_ms"] >= 0

    # First message should have auto-populated the title
    assert payload["title"] == "hi there"


@pytest.mark.asyncio
@respx.mock
async def test_send_message_forwards_trace_context_without_browser_auth(app, client, seeded_user):
    captured_auth_headers: dict[str, str | None] = {}
    captured_inference_headers: dict[str, str | None] = {}

    def auth_handler(request: httpx.Request) -> httpx.Response:
        captured_auth_headers["trace"] = request.headers.get("x-trace-id")
        captured_auth_headers["session_trace"] = request.headers.get("x-session-trace-id")
        return httpx.Response(
            200,
            json={
                "valid": True,
                "user": seeded_user,
                "claims": {"sub": seeded_user["id"]},
            },
        )

    async def inference_handler(request: httpx.Request) -> httpx.Response:
        captured_inference_headers["trace"] = request.headers.get("x-trace-id")
        captured_inference_headers["session_trace"] = request.headers.get("x-session-trace-id")
        captured_inference_headers["user_id"] = request.headers.get("x-user-id")
        captured_inference_headers["authorization"] = request.headers.get("authorization")

        async def body():
            yield b'data: {"token":"ok","gpu":0}\n\n'
            yield b'data: {"done":true}\n\n'

        return httpx.Response(
            200,
            headers={"content-type": "text/event-stream"},
            content=body(),
        )

    respx.mock.post("http://auth.test/auth/validate").mock(side_effect=auth_handler)
    headers = {
        "Authorization": "Bearer valid-token",
        "x-trace-id": "trace-defense-123",
        "x-session-trace-id": "session-defense-456",
    }

    create = await client.post("/api/conversations", json={}, headers=headers)
    assert create.status_code == 201
    convo_id = create.json()["id"]

    app.state.inference_http_client = httpx.AsyncClient(
        transport=httpx.MockTransport(inference_handler)
    )
    try:
        resp = await client.post(
            f"/api/conversations/{convo_id}/messages",
            json={"content": "hi there"},
            headers=headers,
        )
    finally:
        await app.state.inference_http_client.aclose()

    assert resp.status_code == 200
    assert resp.headers["x-session-trace-id"] == "session-defense-456"
    assert captured_auth_headers == {
        "trace": "trace-defense-123",
        "session_trace": "session-defense-456",
    }
    assert captured_inference_headers == {
        "trace": "trace-defense-123",
        "session_trace": "session-defense-456",
        "user_id": seeded_user["id"],
        "authorization": None,
    }


@pytest.mark.asyncio
@respx.mock
async def test_send_message_rejected_on_foreign_conversation(
    app, client, seeded_user, other_user
):
    stub_auth_validate(respx.mock, seeded_user, token="alice-token")
    stub_auth_validate(respx.mock, other_user, token="bob-token")

    alice_headers = {"Authorization": "Bearer alice-token"}
    bob_headers = {"Authorization": "Bearer bob-token"}

    create = await client.post("/api/conversations", json={}, headers=alice_headers)
    convo_id = create.json()["id"]

    app.state.inference_http_client = httpx.AsyncClient(
        transport=_build_inference_mock(["x"])
    )
    try:
        resp = await client.post(
            f"/api/conversations/{convo_id}/messages",
            json={"content": "steal me"},
            headers=bob_headers,
        )
    finally:
        await app.state.inference_http_client.aclose()
    assert resp.status_code == 404


@pytest.mark.asyncio
@respx.mock
async def test_send_message_returns_404_for_missing_conversation(
    app, client, seeded_user
):
    stub_auth_validate(respx.mock, seeded_user)
    headers = {"Authorization": "Bearer valid-token"}

    missing_id = str(uuid.uuid4())
    resp = await client.post(
        f"/api/conversations/{missing_id}/messages",
        json={"content": "hello"},
        headers=headers,
    )
    assert resp.status_code == 404


@pytest.mark.asyncio
@respx.mock
async def test_regenerate_drops_last_assistant_message(app, client, seeded_user):
    stub_auth_validate(respx.mock, seeded_user)
    headers = {"Authorization": "Bearer valid-token"}

    create = await client.post("/api/conversations", json={}, headers=headers)
    convo_id = create.json()["id"]

    app.state.inference_http_client = httpx.AsyncClient(
        transport=_build_inference_mock(["first"])
    )
    try:
        first = await client.post(
            f"/api/conversations/{convo_id}/messages",
            json={"content": "hi"},
            headers=headers,
        )
        assert first.status_code == 200

        app.state.inference_http_client = httpx.AsyncClient(
            transport=_build_inference_mock(["second", " reply"])
        )
        regen = await client.post(
            f"/api/conversations/{convo_id}/regenerate",
            json={},
            headers=headers,
        )
        assert regen.status_code == 200
    finally:
        await app.state.inference_http_client.aclose()

    fetched = await client.get(
        f"/api/conversations/{convo_id}", headers=headers
    )
    messages = fetched.json()["messages"]
    assistant_messages = [m for m in messages if m["role"] == "assistant"]
    assert len(assistant_messages) == 1
    assert assistant_messages[0]["content"] == "second reply"
