import os

import pytest
from starlette.requests import Request
from starlette.responses import Response

from shared.middleware.metrics_guard import MetricsGuardMiddleware


@pytest.mark.asyncio
async def test_metrics_guard_blocks_external_clients(monkeypatch):
    monkeypatch.delenv("METRICS_PUBLIC", raising=False)
    monkeypatch.delenv("METRICS_TOKEN", raising=False)

    middleware = MetricsGuardMiddleware(app=lambda scope, receive, send: None)

    async def call_next(_request):
        return Response(content="ok", media_type="text/plain")

    scope = {
        "type": "http",
        "method": "GET",
        "path": "/metrics",
        "headers": [],
        "client": ("203.0.113.10", 12345),
    }
    request = Request(scope)

    response = await middleware.dispatch(request, call_next)

    assert response.status_code == 403


@pytest.mark.asyncio
async def test_metrics_guard_allows_internal_clients(monkeypatch):
    monkeypatch.delenv("METRICS_PUBLIC", raising=False)

    middleware = MetricsGuardMiddleware(app=lambda scope, receive, send: None)

    async def call_next(_request):
        return Response(content="metrics", media_type="text/plain")

    scope = {
        "type": "http",
        "method": "GET",
        "path": "/metrics",
        "headers": [],
        "client": ("10.42.0.15", 54321),
    }
    request = Request(scope)

    response = await middleware.dispatch(request, call_next)

    assert response.status_code == 200
    assert response.body == b"metrics"


@pytest.mark.asyncio
async def test_metrics_guard_allows_bearer_token(monkeypatch):
    monkeypatch.setenv("METRICS_TOKEN", "secret-token")
    monkeypatch.delenv("METRICS_PUBLIC", raising=False)

    middleware = MetricsGuardMiddleware(app=lambda scope, receive, send: None)

    async def call_next(_request):
        return Response(content="metrics", media_type="text/plain")

    scope = {
        "type": "http",
        "method": "GET",
        "path": "/metrics",
        "headers": [(b"authorization", b"Bearer secret-token")],
        "client": ("203.0.113.10", 12345),
    }
    request = Request(scope)

    response = await middleware.dispatch(request, call_next)

    assert response.status_code == 200
