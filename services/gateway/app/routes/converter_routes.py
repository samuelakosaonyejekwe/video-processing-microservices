from fastapi import APIRouter

router = APIRouter()


@router.post("/upload")
def upload_video():
    return {
        "message": "Video uploaded successfully"
    }


@router.get("/status/{job_id}")
def conversion_status(job_id: str):
    return {
        "job_id": job_id,
        "status": "processing"
    }