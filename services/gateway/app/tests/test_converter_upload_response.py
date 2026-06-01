import io
import os
import uuid

import jwt
import pytest
from fastapi.testclient import TestClient

import app.config as jwt_config
from app.main import app


def _build_access_token(secret: str, algorithm: str) -> str:
    return jwt.encode(
        {"sub": "test-user", "type": "access", "jti": str(uuid.uuid4())},
        secret,
        algorithm=algorithm,
    )


def test_upload_response_includes_s3_key(monkeypatch, tmp_path):
    monkeypatch.setenv("APP_ENV", "test")
    monkeypatch.setenv("JWT_ALGORITHM", "HS256")
    monkeypatch.setenv("JWT_SECRET", "test-secret")
    monkeypatch.setenv("JWT_ISSUER", "video-converter-platform")
    monkeypatch.setenv("JWT_AUDIENCE", "video-converter-users")

    monkeypatch.setattr(jwt_config, "APP_ENV", "test")
    monkeypatch.setattr(jwt_config, "JWT_ALGORITHM", "HS256")
    monkeypatch.setattr(jwt_config, "JWT_SECRET", "test-secret")
    monkeypatch.setattr(jwt_config, "JWT_ISSUER", "video-converter-platform")
    monkeypatch.setattr(jwt_config, "JWT_AUDIENCE", "video-converter-users")

    monkeypatch.setattr(
        "app.routes.converter_routes.upload_video_to_s3",
        lambda source_path, key, content_type: None,
    )
    monkeypatch.setattr(
        "app.routes.converter_routes.create_job",
        lambda **kwargs: True,
    )
    monkeypatch.setattr(
        "app.routes.converter_routes.get_database",
        lambda: object(),
    )
    monkeypatch.setattr(
        "app.routes.converter_routes.enqueue_upload_outbox",
        lambda database, job_id, payload: True,
    )
    monkeypatch.setattr(
        "app.routes.converter_routes.relay_upload_outbox_for_job",
        lambda job_id: "corr-test-id",
    )
    monkeypatch.setattr(
        "app.routes.converter_routes.delete_job",
        lambda job_id: None,
    )

    token = _build_access_token("test-secret", "HS256")

    client = TestClient(app)
    video_bytes = b"\x00\x00\x00\x18ftypisom" + b"\x00" * 64
    response = client.post(
        "/upload",
        headers={"Authorization": f"Bearer {token}"},
        files={"file": ("sample.mp4", io.BytesIO(video_bytes), "video/mp4")},
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["job_id"], body
    assert body["status"] == "uploaded", body
    assert body["correlation_id"] == "corr-test-id", body
    assert body["s3_key"].startswith("uploads/videos/"), body
