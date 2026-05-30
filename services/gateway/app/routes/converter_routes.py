import asyncio
import os
import uuid

from fastapi import APIRouter, File, HTTPException, Request, UploadFile

from app.queue.producer import get_gateway_producer

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

    try:
        correlation_id = await asyncio.to_thread(
            _publish_upload,
            user_id,
            file.filename,
            f"uploads/{job_id}/{file.filename}",
            file.content_type or "application/octet-stream",
        )
    except Exception as exc:
        raise HTTPException(
            status_code=503,
            detail=f"Upload queue unavailable: {exc.__class__.__name__}",
        ) from exc

    return {
        "job_id": job_id,
        "correlation_id": correlation_id,
        "status": "uploaded",
    }


def _publish_upload(user_id, filename, s3_key, content_type):

    producer = get_gateway_producer()
    return producer.publish_video_upload_event(
        user_id=user_id,
        filename=filename,
        s3_key=s3_key,
        content_type=content_type,
    )
