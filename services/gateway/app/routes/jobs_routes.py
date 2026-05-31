from fastapi import APIRouter, HTTPException, Request

from app.database.job_repository import get_job
from app.storage.s3_storage import (
    _audio_bucket,
    audio_object_key,
    generate_presigned_download_url,
    object_exists,
)

router = APIRouter(tags=["Jobs"])


def _status_from_mongo(job_id: str) -> dict | None:
    job = get_job(job_id)
    if not job:
        return None

    response = {
        "job_id": job_id,
        "status": job.get("status", "processing"),
    }
    audio_key = job.get("audio_s3_key")
    if audio_key:
        response["audio_key"] = audio_key
    return response


def _status_from_s3(job_id: str) -> dict:
    bucket = _audio_bucket()
    if not bucket:
        raise HTTPException(status_code=503, detail="Audio storage is not configured")

    audio_key = audio_object_key(job_id)
    if object_exists(bucket, audio_key):
        return {
            "job_id": job_id,
            "status": "completed",
            "audio_key": audio_key,
        }

    return {
        "job_id": job_id,
        "status": "processing",
    }


@router.get("/jobs/{job_id}/status")
async def get_job_status(job_id: str):
    mongo_status = _status_from_mongo(job_id)
    if mongo_status:
        if mongo_status["status"] == "completed":
            return mongo_status
        # Still processing in MongoDB; confirm S3 in case completion event was missed.
        s3_status = _status_from_s3(job_id)
        if s3_status["status"] == "completed":
            return s3_status
        return mongo_status

    return _status_from_s3(job_id)


@router.get("/jobs/{job_id}/download")
async def download_job_audio(job_id: str, request: Request):
    bucket = _audio_bucket()
    if not bucket:
        raise HTTPException(status_code=503, detail="Audio storage is not configured")

    job = get_job(job_id)
    audio_key = None
    if job and job.get("audio_s3_key"):
        audio_key = job["audio_s3_key"]
    else:
        audio_key = audio_object_key(job_id)

    if not object_exists(bucket, audio_key):
        raise HTTPException(
            status_code=404,
            detail="Audio not ready yet. Conversion may still be in progress.",
        )

    original_name = request.query_params.get("filename")
    if not original_name and job:
        original_name = job.get("filename")
    if not original_name:
        original_name = f"{job_id}.mp3"

    base_name = original_name.rsplit(".", 1)[0]
    download_name = f"{base_name}.mp3"

    try:
        download_url = generate_presigned_download_url(bucket, audio_key, download_name)
    except RuntimeError as error:
        raise HTTPException(status_code=503, detail=str(error)) from error

    return {
        "job_id": job_id,
        "download_url": download_url,
        "filename": download_name,
    }
