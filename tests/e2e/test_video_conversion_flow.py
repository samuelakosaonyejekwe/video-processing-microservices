import os
import uuid

import requests


def test_video_upload_flow():

    gateway_url = os.getenv("GATEWAY_BASE_URL", "http://localhost:8080")
    auth_url = os.getenv("AUTH_BASE_URL", gateway_url)

    email = f"e2e-{uuid.uuid4().hex[:8]}@example.com"
    password = "TestPassword123!"
    username = f"e2euser-{uuid.uuid4().hex[:6]}"

    register = requests.post(
        f"{auth_url}/auth/register",
        json={
            "username": username,
            "email": email,
            "password": password,
        },
        timeout=15,
    )
    assert register.status_code in [200, 201, 409], register.text

    login = requests.post(
        f"{auth_url}/auth/login",
        json={
            "email": email,
            "password": password,
        },
        timeout=15,
    )
    assert login.status_code == 200, login.text

    token = login.json().get("access_token")
    assert token

    files = {
        "file": ("sample.bin", b"integration-test-payload", "application/octet-stream"),
    }

    response = requests.post(
        f"{gateway_url}/upload",
        headers={"Authorization": f"Bearer {token}"},
        files=files,
        timeout=30,
    )

    assert response.status_code in [200, 201, 202], response.text

    body = response.json()
    assert body.get("job_id"), body
    assert body.get("status") == "uploaded", body
    assert body.get("correlation_id"), body
