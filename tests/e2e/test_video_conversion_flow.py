import os
import time
import uuid
from pathlib import Path

import httpx
import pytest

from shared.storage.s3_client import create_s3_client

FIXTURE_PATH = (
    Path(__file__).resolve().parent.parent / "fixtures" / "sample-with-audio.mp4"
)


def _production_validation_enabled() -> bool:
    return os.getenv("PRODUCTION_VALIDATION", "").lower() in ("1", "true", "yes")


def _audio_bucket() -> str:
    return os.getenv("S3_AUDIO_BUCKET") or os.getenv("AWS_S3_AUDIO_BUCKET") or ""


def _video_bucket() -> str:
    return (
        os.getenv("S3_UPLOAD_BUCKET")
        or os.getenv("AWS_S3_VIDEO_BUCKET")
        or os.getenv("AWS_S3_BUCKET")
        or os.getenv("S3_BUCKET_NAME")
        or ""
    )


def _require_production_buckets() -> tuple[str, str]:
    audio_bucket = _audio_bucket()
    video_bucket = _video_bucket()

    missing = []
    if not audio_bucket:
        missing.append("S3_AUDIO_BUCKET or AWS_S3_AUDIO_BUCKET")
    if not video_bucket:
        missing.append("S3_UPLOAD_BUCKET or AWS_S3_VIDEO_BUCKET or AWS_S3_BUCKET or S3_BUCKET_NAME")

    if missing:
        pytest.skip(
            "PRODUCTION_VALIDATION skipped because required S3 bucket env vars are missing: "
            + ", ".join(missing)
        )

    return video_bucket, audio_bucket


def _assert_s3_object_exists(bucket: str, key: str) -> None:
    from botocore.exceptions import ClientError

    client = create_s3_client()

    try:
        client.head_object(Bucket=bucket, Key=key)
    except ClientError as error:
        raise AssertionError(
            f"Expected s3://{bucket}/{key} to exist after upload: {error}"
        ) from error


def _list_mp3_keys(bucket: str) -> set[str]:
    prefix = os.getenv("S3_AUDIO_OUTPUT_PREFIX", "outputs/audio/").rstrip("/") + "/"
    client = create_s3_client()
    keys: set[str] = set()

    paginator = client.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for item in page.get("Contents", []):
            if item["Key"].endswith(".mp3"):
                keys.add(item["Key"])

    return keys


def _wait_for_new_audio_object(
    bucket: str, existing_keys: set[str], timeout_seconds: int = 60
) -> str:
    deadline = time.time() + timeout_seconds

    while time.time() < deadline:
        current_keys = _list_mp3_keys(bucket)
        new_keys = current_keys - existing_keys
        if new_keys:
            return sorted(new_keys)[-1]
        time.sleep(5)

    raise AssertionError(
        f"Timed out waiting for converted audio in s3://{bucket}/ after {timeout_seconds}s"
    )


def test_video_upload_flow():
    gateway_url = os.getenv("GATEWAY_BASE_URL", "http://localhost:8080").rstrip("/")

    assert FIXTURE_PATH.is_file(), f"Missing test fixture: {FIXTURE_PATH}"

    email = f"e2e-{uuid.uuid4().hex[:8]}@example.com"
    password = "TestPassword123!"
    username = f"e2euser-{uuid.uuid4().hex[:6]}"

    existing_audio_keys: set[str] = set()
    video_bucket = ""
    audio_bucket = ""
    if _production_validation_enabled():
        video_bucket, audio_bucket = _require_production_buckets()
        existing_audio_keys = _list_mp3_keys(audio_bucket)

    with httpx.Client(base_url=gateway_url, timeout=30.0) as client:
        register = client.post(
            "/auth/register",
            json={
                "username": username,
                "email": email,
                "password": password,
            },
        )
        assert register.status_code in [200, 201, 409], register.text

        login = client.post(
            "/auth/login",
            json={
                "email": email,
                "password": password,
            },
        )
        assert login.status_code == 200, login.text
        assert "access_token" in login.cookies
        # httpx doesn't propagate httponly cookies for localhost automatically
        client.cookies.set("access_token", login.cookies["access_token"])

        with FIXTURE_PATH.open("rb") as fixture:
            response = client.post(
                "/upload",
                files={
                    "file": ("sample-with-audio.mp4", fixture, "video/mp4"),
                },
            )

    assert response.status_code in [200, 201, 202], response.text

    body = response.json()
    job_id = body.get("job_id")
    assert job_id, body
    assert body.get("status") == "uploaded", body
    assert body.get("correlation_id"), body
    assert body.get("s3_key"), body

    if _production_validation_enabled():
        video_s3_key = body["s3_key"]
        _assert_s3_object_exists(video_bucket, video_s3_key)
        audio_key = _wait_for_new_audio_object(audio_bucket, existing_audio_keys)
        assert audio_key.endswith(".mp3"), audio_key
