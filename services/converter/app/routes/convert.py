import os
import uuid

from fastapi import APIRouter, File, UploadFile

from app.queue.producer import publish_conversion_job

router = APIRouter(tags=["Converter"])

TEMP_DIR = os.getenv("TEMP_STORAGE_PATH", "/tmp")


@router.post("/convert")
async def convert_video(file: UploadFile = File(...)):

    job_id = str(uuid.uuid4())

    temp_path = os.path.join(TEMP_DIR, f"{job_id}-{file.filename}")

    content = await file.read()

    with open(temp_path, "wb") as temp_file:
        temp_file.write(content)

    correlation_id = publish_conversion_job(
        job_id=job_id,
        filename=file.filename,
        local_path=temp_path,
        content_type=file.content_type or "application/octet-stream",
    )

    return {
        "message": "Conversion job queued",
        "job_id": job_id,
        "correlation_id": correlation_id,
        "status": "queued",
    }
