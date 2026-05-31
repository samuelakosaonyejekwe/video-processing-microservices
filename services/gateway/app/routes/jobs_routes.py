from fastapi import APIRouter, HTTPException, Request

from app.storage.s3_storage import (
    _audio_bucket,
    audio_object_key,
    generate_presigned_download_url,
    object_exists,
)

router = APIRouter(tags=["Jobs"])


@router.get("/jobs/{job_id}/status")
async def get_job_status(job_id: str):
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


@router.get("/jobs/{job_id}/download")
async def download_job_audio(job_id: str, request: Request):
    bucket = _audio_bucket()
    if not bucket:
        raise HTTPException(status_code=503, detail="Audio storage is not configured")

    audio_key = audio_object_key(job_id)
    if not object_exists(bucket, audio_key):
        raise HTTPException(
            status_code=404,
            detail="Audio not ready yet. Conversion may still be in progress.",
        )

    original_name = request.query_params.get("filename", f"{job_id}.mp3")
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
