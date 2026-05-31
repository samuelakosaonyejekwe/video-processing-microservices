import os

import httpx
import pytest

GATEWAY_BASE_URL = os.getenv("GATEWAY_BASE_URL", "http://localhost:8080").rstrip("/")


@pytest.mark.e2e
def test_gateway_session_uses_cookie_not_bearer():
    username = f"cookie_user_{os.getpid()}"
    email = f"{username}@example.com"
    password = "SecurePass1"

    with httpx.Client(base_url=GATEWAY_BASE_URL, timeout=30.0) as client:
        register_response = client.post(
            "/auth/register",
            json={
                "username": username,
                "email": email,
                "password": password,
            },
        )
        assert register_response.status_code in (200, 201, 409)

        login_response = client.post(
            "/auth/login",
            json={"email": email, "password": password},
        )
        assert login_response.status_code == 200
        assert "access_token" in login_response.cookies

        session_response = client.get("/auth/session")
        assert session_response.status_code == 200
        body = session_response.json()
        assert body.get("authenticated") is True
        assert body.get("email") == email
