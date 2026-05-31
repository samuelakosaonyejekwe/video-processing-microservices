import os
import time
import uuid
from pathlib import Path

import requests

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

    if not audio_bucket:
        raise AssertionError(
            "PRODUCTION_VALIDATION requires S3_AUDIO_BUCKET or AWS_S3_AUDIO_BUCKET"
        )
    if not video_bucket:
        raise AssertionError(
            "PRODUCTION_VALIDATION requires S3_UPLOAD_BUCKET or AWS_S3_VIDEO_BUCKET"
        )

    return video_bucket, audio_bucket


def _assert_s3_object_exists(bucket: str, key: str) -> None:
    import boto3
    from botocore.exceptions import ClientError

    region = os.getenv("AWS_REGION", "eu-central-1")
    client = boto3.client("s3", region_name=region)

    try:
        client.head_object(Bucket=bucket, Key=key)
    except ClientError as error:
        raise AssertionError(
            f"Expected s3://{bucket}/{key} to exist after upload: {error}"
        ) from error


def _list_mp3_keys(bucket: str) -> set[str]:
    import boto3

    prefix = os.getenv("S3_AUDIO_OUTPUT_PREFIX", "outputs/audio/").rstrip("/") + "/"
    region = os.getenv("AWS_REGION", "eu-central-1")
    client = boto3.client("s3", region_name=region)
    keys: set[str] = set()

    paginator = client.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            if obj["Key"].endswith(".mp3"):
                keys.add(obj["Key"])

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
    gateway_url = os.getenv("GATEWAY_BASE_URL", "http://localhost:8080")
    auth_url = os.getenv("AUTH_BASE_URL", gateway_url)

    assert FIXTURE_PATH.is_file(), f"Missing test fixture: {FIXTURE_PATH}"

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

    existing_audio_keys: set[str] = set()
    video_bucket = ""
    audio_bucket = ""
    if _production_validation_enabled():
        video_bucket, audio_bucket = _require_production_buckets()
        existing_audio_keys = _list_mp3_keys(audio_bucket)

    with FIXTURE_PATH.open("rb") as fixture:
        files = {
            "file": ("sample-with-audio.mp4", fixture, "video/mp4"),
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
    assert body.get("s3_key"), body

    if _production_validation_enabled():
        _assert_s3_object_exists(video_bucket, body["s3_key"])
        audio_key = _wait_for_new_audio_object(audio_bucket, existing_audio_keys)
        assert audio_key.endswith(".mp3"), audio_key
