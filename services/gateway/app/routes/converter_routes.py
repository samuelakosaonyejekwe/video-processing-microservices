import asyncio
import logging
import os
import uuid

from fastapi import APIRouter, File, HTTPException, Request, UploadFile

from app.database.job_repository import create_job, delete_job
from app.queue.producer import get_gateway_producer
from app.storage.s3_storage import delete_object, upload_video_to_s3, _video_bucket
from shared.security.upload_validation import (
    sanitize_filename,
    validate_content_type,
    validate_upload_size,
    validate_video_extension,
)

logger = logging.getLogger(__name__)

router = APIRouter(tags=["Converter"])


@router.post("/upload")
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

    content_type = file.content_type or "application/octet-stream"
    if not validate_content_type(content_type):
        raise HTTPException(status_code=400, detail="Invalid content type for upload")

    content = await file.read()
    try:
        validate_upload_size(len(content))
    except ValueError as error:
        raise HTTPException(status_code=413, detail=str(error)) from error

    job_id = str(uuid.uuid4())
    temp_dir = os.getenv("TEMP_STORAGE_PATH", "/tmp")
    temp_file_path = os.path.join(temp_dir, f"{job_id}-{safe_filename}")

    user_id = "anonymous"
    user_email = None

    if hasattr(request.state, "user"):
        user_id = request.state.user.get("sub", user_id)
        user_email = request.state.user.get("email")

    s3_key = f"uploads/videos/{job_id}/{safe_filename}"
    s3_uploaded = False
    job_persisted = False

    try:
        with open(temp_file_path, "wb") as temp_file:
            temp_file.write(content)

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

        correlation_id = await asyncio.to_thread(
            _publish_upload,
            job_id,
            user_id,
            safe_filename,
            s3_key,
            content_type,
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
        "s3_key": s3_key,
        "correlation_id": correlation_id,
    }


def _publish_upload(job_id, user_id, filename, s3_key, content_type):

    producer = get_gateway_producer()
    return producer.publish_video_upload_event(
        job_id=job_id,
        user_id=user_id,
        filename=filename,
        s3_key=s3_key,
        content_type=content_type,
    )
