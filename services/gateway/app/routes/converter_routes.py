import asyncio
import logging
import os
import uuid
from typing import Optional

import httpx
from pydantic import BaseModel
from fastapi import APIRouter, File, HTTPException, Request, UploadFile

from app.config import JWT_AUTH_SERVICE_URL
from app.database.mongo_client import get_database
from app.database.job_repository import create_job, delete_job
from app.outbox.upload_relay import relay_upload_outbox_for_job
from app.storage.s3_storage import delete_object, upload_video_to_s3, _video_bucket
from shared.http.internal_client import internal_http_client
from shared.outbox.upload_outbox import enqueue_upload_outbox
from shared.security.upload_validation import (
    sanitize_filename,
    validate_content_type,
    validate_upload_size,
    validate_video_extension,
    validate_video_magic_bytes,
)

logger = logging.getLogger(__name__)

router = APIRouter(tags=["Converter"])


def _request_token(request: Request) -> str | None:
    authorization = request.headers.get("Authorization")
    if authorization:
        parts = authorization.split()
        if len(parts) == 2 and parts[0].lower() == "bearer":
            return parts[1]
    return request.cookies.get("access_token")


async def _resolve_user_email(request: Request) -> str | None:
    """Look up the user's email from the auth service.

    Email is deliberately absent from the JWT (PII), so we resolve it from the
    source of truth using the caller's access token. Failures are non-fatal:
    the upload still succeeds, only the completion email is skipped.
    """
    if os.getenv("APP_ENV") == "test":
        return None

    token = _request_token(request)
    if not token:
        return None

    try:
        async with internal_http_client(timeout=5.0) as client:
            response = await client.get(
                f"{JWT_AUTH_SERVICE_URL}/auth/me",
                headers={"Authorization": f"Bearer {token}"},
            )
    except httpx.HTTPError as error:
        logger.warning("Failed to resolve user email from auth service: %s", error)
        return None

    if response.status_code == 200:
        return response.json().get("email")

    logger.warning(
        "Auth service /auth/me returned status %s while resolving email",
        response.status_code,
    )
    return None


class UploadResponse(BaseModel):
    job_id: str
    status: str
    correlation_id: Optional[str] = None
    s3_key: str


@router.post("/upload", response_model=UploadResponse)
async def upload_video(
    request: Request,
    file: UploadFile = File(...),
):

    if not file.filename:
        raise HTTPException(status_code=400, detail="Filename is required")

    try:
        safe_filename = sanitize_filename(file.filename)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error

    if not validate_video_extension(safe_filename):
        raise HTTPException(
            status_code=400,
            detail="Unsupported video format. Allowed: mp4, mov, avi, mkv, webm",
        )

    # Validate the content type the client actually declared. A missing header
    # is tolerated (magic-byte validation below is the real gate), but an
    # explicit non-video type such as application/octet-stream is rejected.
    if not validate_content_type(file.content_type):
        raise HTTPException(status_code=400, detail="Invalid content type for upload")
    content_type = file.content_type or "application/octet-stream"

    max_upload_bytes = int(os.getenv("MAX_VIDEO_UPLOAD_SIZE_MB", "500")) * 1024 * 1024
    chunk_size = 1024 * 1024
    total_bytes = 0
    header_sample = b""

    job_id = str(uuid.uuid4())
    temp_dir = os.getenv("TEMP_STORAGE_PATH", "/tmp")
    temp_file_path = os.path.join(temp_dir, f"{job_id}-{safe_filename}")

    s3_key = f"uploads/videos/{job_id}/{safe_filename}"
    s3_uploaded = False
    job_persisted = False

    # Single try/finally from temp-file creation onward guarantees the temp file
    # is removed on every exit path, including client disconnects or unexpected
    # errors during streaming/validation.
    try:
        with open(temp_file_path, "wb") as temp_file:
            while True:
                chunk = await file.read(chunk_size)
                if not chunk:
                    break
                total_bytes += len(chunk)
                if total_bytes > max_upload_bytes:
                    raise HTTPException(
                        status_code=413,
                        detail=(
                            "Upload exceeds maximum size of "
                            f"{max_upload_bytes // (1024 * 1024)} MB"
                        ),
                    )
                if len(header_sample) < 16:
                    header_sample += chunk[: 16 - len(header_sample)]
                temp_file.write(chunk)

        try:
            validate_upload_size(total_bytes)
        except ValueError as error:
            raise HTTPException(status_code=413, detail=str(error)) from error

        if not validate_video_magic_bytes(header_sample[:16]):
            raise HTTPException(
                status_code=400,
                detail="Uploaded file is not a supported video format",
            )

        if not hasattr(request.state, "user") or not request.state.user.get("sub"):
            raise HTTPException(status_code=401, detail="Not authenticated")

        user_id = str(request.state.user.get("sub"))
        user_email = await _resolve_user_email(request)

        try:
            await asyncio.to_thread(
                upload_video_to_s3,
                temp_file_path,
                s3_key,
                content_type,
            )
            s3_uploaded = True

            job_persisted = await asyncio.to_thread(
                create_job,
                job_id=job_id,
                user_id=user_id,
                user_email=user_email,
                filename=safe_filename,
                video_s3_key=s3_key,
                content_type=content_type,
            )
            if not job_persisted:
                raise RuntimeError("Failed to persist job metadata")

            database = get_database()
            outbox_payload = {
                "job_id": job_id,
                "user_id": user_id,
                "filename": safe_filename,
                "s3_key": s3_key,
                "content_type": content_type,
            }
            if database is not None and not enqueue_upload_outbox(
                database, job_id=job_id, payload=outbox_payload
            ):
                raise RuntimeError("Failed to persist upload outbox entry")

            correlation_id = await asyncio.to_thread(
                relay_upload_outbox_for_job, job_id
            )
        except HTTPException:
            raise
        except Exception as exc:
            logger.exception("Upload failed job_id=%s", job_id)
            if s3_uploaded:
                bucket = _video_bucket()
                if bucket:
                    try:
                        await asyncio.to_thread(delete_object, bucket, s3_key)
                    except Exception as cleanup_error:
                        logger.warning(
                            "Failed to rollback S3 upload job_id=%s: %s",
                            job_id,
                            cleanup_error,
                        )
            if job_persisted:
                await asyncio.to_thread(delete_job, job_id)
            raise HTTPException(
                status_code=503,
                detail="Upload failed. Please try again later.",
            ) from exc
    finally:
        if os.path.exists(temp_file_path):
            os.remove(temp_file_path)

    return {
        "job_id": job_id,
        "status": "uploaded",
        "correlation_id": correlation_id,
        "s3_key": s3_key,
    }
