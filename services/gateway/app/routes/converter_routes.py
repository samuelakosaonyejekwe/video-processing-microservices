import os
import uuid

from fastapi import APIRouter, File, Request, UploadFile

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

    producer = get_gateway_producer()

    correlation_id = producer.publish_video_upload_event(
        user_id=user_id,
        filename=file.filename,
        s3_key=f"uploads/{job_id}/{file.filename}",
        content_type=file.content_type or "application/octet-stream",
    )

    return {
        "job_id": job_id,
        "correlation_id": correlation_id,
        "status": "uploaded",
    }
