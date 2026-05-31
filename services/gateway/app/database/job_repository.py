import logging
from datetime import datetime, timezone

from pymongo import ASCENDING, ReturnDocument

from app.database.mongo_client import get_database, is_mongo_configured

logger = logging.getLogger(__name__)

JOBS_COLLECTION = "conversion_jobs"


def _collection():
    database = get_database()
    if database is None:
        return None
    return database[JOBS_COLLECTION]


def ensure_job_indexes() -> None:
    collection = _collection()
    if collection is None:
        return

    try:
        collection.create_index([("job_id", ASCENDING)], unique=True)
        collection.create_index([("user_id", ASCENDING), ("created_at", ASCENDING)])
        collection.create_index([("status", ASCENDING)])
    except Exception as error:
        logger.warning("MongoDB index setup failed: %s", error)


def create_job(
    *,
    job_id: str,
    user_id: str,
    user_email: str | None,
    filename: str,
    video_s3_key: str,
    content_type: str,
) -> bool:
    collection = _collection()
    if collection is None:
        logger.warning("MongoDB unavailable; job %s not persisted", job_id)
        return False

    ensure_job_indexes()

    now = datetime.now(timezone.utc)
    document = {
        "job_id": job_id,
        "user_id": user_id,
        "user_email": user_email,
        "filename": filename,
        "video_s3_key": video_s3_key,
        "content_type": content_type,
        "status": "processing",
        "audio_s3_key": None,
        "notification_sent": False,
        "created_at": now,
        "updated_at": now,
        "completed_at": None,
    }

    try:
        collection.insert_one(document)
    except Exception as error:
        logger.warning("MongoDB job persist failed job_id=%s: %s", job_id, error)
        return False

    logger.info("Job persisted job_id=%s user_id=%s", job_id, user_id)
    return True


def get_job(job_id: str) -> dict | None:
    collection = _collection()
    if collection is None:
        return None

    job = collection.find_one({"job_id": job_id}, {"_id": 0})
    return job


def mark_job_completed(job_id: str, audio_s3_key: str) -> dict | None:
    collection = _collection()
    if collection is None:
        return None

    now = datetime.now(timezone.utc)
    return collection.find_one_and_update(
        {"job_id": job_id},
        {
            "$set": {
                "status": "completed",
                "audio_s3_key": audio_s3_key,
                "updated_at": now,
                "completed_at": now,
            }
        },
        return_document=ReturnDocument.AFTER,
        projection={"_id": 0},
    )


def claim_notification_send(job_id: str) -> dict | None:
    """Return job eligible for notification without marking sent yet."""
    collection = _collection()
    if collection is None:
        return None

    return collection.find_one(
        {
            "job_id": job_id,
            "status": "completed",
            "notification_sent": {"$ne": True},
            "user_email": {"$nin": [None, ""]},
        },
        projection={"_id": 0},
    )


def mark_notification_sent(job_id: str) -> None:
    collection = _collection()
    if collection is None:
        return

    now = datetime.now(timezone.utc)
    collection.update_one(
        {"job_id": job_id},
        {"$set": {"notification_sent": True, "updated_at": now}},
    )


def mongo_available() -> bool:
    if not is_mongo_configured():
        return False
    return get_database() is not None
