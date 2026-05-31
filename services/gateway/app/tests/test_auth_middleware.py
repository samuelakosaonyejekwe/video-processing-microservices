import os

import jwt
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.middleware.auth_middleware import AuthMiddleware


@pytest.fixture
def strict_cookie_app(monkeypatch):
    monkeypatch.setenv("STRICT_COOKIE_AUTH", "true")
    monkeypatch.setenv("APP_ENV", "test")

    app = FastAPI()
    app.add_middleware(AuthMiddleware)

    @app.get("/protected")
    async def protected():
        return {"ok": True}

    return app


def test_strict_cookie_auth_rejects_bearer_header(strict_cookie_app):
    client = TestClient(strict_cookie_app)
    response = client.get(
        "/protected",
        headers={"Authorization": "Bearer fake-token"},
    )
    assert response.status_code == 401
    assert "cookie session" in response.json()["detail"].lower()


def test_strict_cookie_auth_allows_access_cookie(strict_cookie_app, monkeypatch):
    import app.config as jwt_config

    monkeypatch.setattr(jwt_config, "JWT_ALGORITHM", "HS256")
    monkeypatch.setattr(jwt_config, "JWT_SECRET", "test-secret")
    monkeypatch.setattr(jwt_config, "JWT_PUBLIC_KEY", "")
    monkeypatch.setattr(jwt_config, "JWT_ISSUER", None)
    monkeypatch.setattr(jwt_config, "JWT_AUDIENCE", None)

    token = jwt.encode(
        {"sub": "user-1", "type": "access"},
        "test-secret",
        algorithm="HS256",
    )

    client = TestClient(strict_cookie_app)
    client.cookies.set("access_token", token)
    response = client.get("/protected")

    assert response.status_code == 200
    assert response.json() == {"ok": True}
