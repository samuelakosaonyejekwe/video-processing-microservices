import asyncio
import re

from fastapi import APIRouter, HTTPException, Request

from app.database.job_repository import get_job
from app.storage.s3_storage import (
    _audio_bucket,
    audio_object_key,
    generate_presigned_download_url,
    object_exists,
)

router = APIRouter(tags=["Jobs"])

# Strip anything that isn't a safe filename character before it is reflected
# into the Content-Disposition header of the presigned URL.
_SAFE_FILENAME = re.compile(r"[^A-Za-z0-9._-]+")


def _safe_download_name(raw: str, job_id: str) -> str:
    base = (raw or "").rsplit(".", 1)[0]
    base = _SAFE_FILENAME.sub("_", base).strip("._") or job_id
    return f"{base}.mp3"


def _get_authenticated_user_id(request: Request) -> str:
    if not hasattr(request.state, "user"):
        raise HTTPException(status_code=401, detail="Not authenticated")

    user_id = request.state.user.get("sub")
    if not user_id:
        raise HTTPException(status_code=401, detail="Not authenticated")
    return str(user_id)


def _authorize_job_access(job_id: str, request: Request) -> dict:
    job = get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")

    user_id = _get_authenticated_user_id(request)
    job_user_id = job.get("user_id")

    if job_user_id in (None, "", "anonymous") or str(job_user_id) != user_id:
        raise HTTPException(status_code=404, detail="Job not found")

    return job


def _status_from_mongo(job: dict, job_id: str) -> dict:
    response = {
        "job_id": job_id,
        "status": job.get("status", "processing"),
    }
    if job.get("error_message"):
        response["error_message"] = job["error_message"]
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
async def get_job_status(job_id: str, request: Request):
    job = await asyncio.to_thread(_authorize_job_access, job_id, request)
    mongo_status = _status_from_mongo(job, job_id)

    if mongo_status["status"] in ("completed", "failed"):
        return mongo_status

    s3_status = await asyncio.to_thread(_status_from_s3, job_id)
    if s3_status["status"] == "completed":
        return s3_status

    return mongo_status


@router.get("/jobs/{job_id}/download")
async def download_job_audio(job_id: str, request: Request):
    bucket = _audio_bucket()
    if not bucket:
        raise HTTPException(status_code=503, detail="Audio storage is not configured")

    job = await asyncio.to_thread(_authorize_job_access, job_id, request)
    if job.get("status") == "failed":
        raise HTTPException(status_code=404, detail="Conversion failed for this job")

    audio_key = job.get("audio_s3_key") or audio_object_key(job_id)

    if not await asyncio.to_thread(object_exists, bucket, audio_key):
        raise HTTPException(
            status_code=404,
            detail="Audio not ready yet. Conversion may still be in progress.",
        )

    original_name = (
        request.query_params.get("filename") or job.get("filename") or f"{job_id}.mp3"
    )
    download_name = _safe_download_name(original_name, job_id)

    try:
        download_url = await asyncio.to_thread(
            generate_presigned_download_url, bucket, audio_key, download_name
        )
    except RuntimeError as error:
        raise HTTPException(status_code=503, detail="Download unavailable") from error

    return {
        "job_id": job_id,
        "download_url": download_url,
        "filename": download_name,
    }
