import asyncio
import logging
import os
import uuid

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile

from app.config import MAX_CONVERSION_TIMEOUT_SECONDS
from app.dependencies.auth import require_access_token
from app.queue.producer import publish_conversion_job
from shared.security.upload_validation import (
    get_max_upload_size_bytes,
    sanitize_filename,
    validate_content_type,
    validate_video_extension,
    validate_video_magic_bytes,
)
from shared.storage.s3_client import create_s3_client

logger = logging.getLogger(__name__)

router = APIRouter(tags=["Converter"])

TEMP_DIR = os.getenv("TEMP_STORAGE_PATH", "/tmp")


def _upload_bucket() -> str:
    return (
        os.getenv("S3_UPLOAD_BUCKET")
        or os.getenv("AWS_S3_VIDEO_BUCKET")
        or os.getenv("AWS_S3_BUCKET")
        or os.getenv("S3_BUCKET_NAME")
        or ""
    )


@router.post("/convert")
async def convert_video(
    file: UploadFile = File(...),
    user: dict = Depends(require_access_token),
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

    # Validate the declared content type (missing header tolerated; magic-byte
    # check below is the real gate; explicit non-video types rejected).
    if not validate_content_type(file.content_type):
        raise HTTPException(status_code=400, detail="Invalid content type for upload")
    content_type = file.content_type or "application/octet-stream"

    bucket = _upload_bucket()
    if not bucket:
        raise HTTPException(status_code=503, detail="Upload storage is not configured")

    job_id = str(uuid.uuid4())
    temp_path = os.path.join(TEMP_DIR, f"{job_id}-{safe_filename}")
    s3_key = f"uploads/videos/{job_id}/{safe_filename}"
    user_id = user.get("sub", "anonymous")

    max_upload_bytes = get_max_upload_size_bytes()
    chunk_size = 1024 * 1024
    total_bytes = 0
    header_sample = b""

    # Stream to a temp file in bounded chunks instead of buffering the whole
    # upload in memory (a few large/oversized uploads would otherwise OOM).
    try:
        with open(temp_path, "wb") as temp_file:
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

        if not validate_video_magic_bytes(header_sample[:16]):
            raise HTTPException(
                status_code=400,
                detail="Uploaded file is not a supported video format",
            )

        client = create_s3_client()
        await asyncio.to_thread(
            client.upload_file,
            temp_path,
            bucket,
            s3_key,
            ExtraArgs={"ContentType": content_type},
        )

        correlation_id = await asyncio.to_thread(
            publish_conversion_job,
            job_id=job_id,
            filename=safe_filename,
            s3_key=s3_key,
            content_type=content_type,
            user_id=user_id,
        )
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Direct convert request failed job_id=%s", job_id)
        raise HTTPException(
            status_code=503,
            detail="Failed to queue conversion job",
        ) from exc
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)

    return {
        "message": "Conversion job queued",
        "job_id": job_id,
        "correlation_id": correlation_id,
        "status": "queued",
        "timeout_seconds": MAX_CONVERSION_TIMEOUT_SECONDS,
    }
