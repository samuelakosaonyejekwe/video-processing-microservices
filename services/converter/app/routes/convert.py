import asyncio
import logging
import os
import uuid

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile

from app.config import MAX_CONVERSION_TIMEOUT_SECONDS
from app.dependencies.auth import require_access_token
from app.queue.producer import publish_conversion_job
from shared.security.upload_validation import (
    sanitize_filename,
    validate_content_type,
    validate_upload_size,
    validate_video_extension,
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

    content_type = file.content_type or "application/octet-stream"
    if not validate_content_type(content_type):
        raise HTTPException(status_code=400, detail="Invalid content type for upload")

    content = await file.read()
    try:
        validate_upload_size(len(content))
    except ValueError as error:
        raise HTTPException(status_code=413, detail=str(error)) from error

    job_id = str(uuid.uuid4())
    temp_path = os.path.join(TEMP_DIR, f"{job_id}-{safe_filename}")
    bucket = _upload_bucket()
    if not bucket:
        raise HTTPException(status_code=503, detail="Upload storage is not configured")

    s3_key = f"uploads/videos/{job_id}/{safe_filename}"
    user_id = user.get("sub", "anonymous")

    try:
        with open(temp_path, "wb") as temp_file:
            temp_file.write(content)

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
