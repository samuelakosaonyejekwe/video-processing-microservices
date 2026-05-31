import asyncio
import os
import uuid

from fastapi import APIRouter, File, HTTPException, Request, UploadFile

from app.queue.producer import get_gateway_producer
from app.storage.s3_storage import upload_video_to_s3

router = APIRouter(tags=["Converter"])


@router.post("/upload")
async def upload_video(
    request: Request,
    file: UploadFile = File(...),
):

    job_id = str(uuid.uuid4())

    temp_dir = os.getenv("TEMP_STORAGE_PATH", "/tmp")
    temp_file_path = os.path.join(temp_dir, f"{job_id}-{file.filename}")

    content = await file.read()

    with open(temp_file_path, "wb") as temp_file:
        temp_file.write(content)

    user_id = "anonymous"

    if hasattr(request.state, "user"):
        user_id = request.state.user.get("sub", user_id)

    content_type = file.content_type or "application/octet-stream"
    s3_key = f"uploads/videos/{job_id}/{file.filename}"

    try:
        await asyncio.to_thread(
            upload_video_to_s3,
            temp_file_path,
            s3_key,
            content_type,
        )
        correlation_id = await asyncio.to_thread(
            _publish_upload,
            job_id,
            user_id,
            file.filename,
            s3_key,
            content_type,
        )
    except Exception as exc:
        raise HTTPException(
            status_code=503,
            detail=f"Upload failed: {exc.__class__.__name__}: {exc}",
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
