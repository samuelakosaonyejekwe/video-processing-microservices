import logging
import os
from datetime import datetime, timezone
from typing import Any

logger = logging.getLogger(__name__)

UPLOAD_OUTBOX_COLLECTION = "upload_outbox"
MAX_UPLOAD_OUTBOX_ATTEMPTS = int(os.getenv("MAX_UPLOAD_OUTBOX_ATTEMPTS", "5"))


def _collection(database):
    if database is None:
        return None
    return database[UPLOAD_OUTBOX_COLLECTION]


def ensure_upload_outbox_indexes(database) -> None:
    collection = _collection(database)
    if collection is None:
        return
    try:
        collection.create_index([("job_id", 1)], unique=True)
        collection.create_index([("status", 1), ("updated_at", 1)])
    except Exception as error:
        logger.warning("Upload outbox index setup failed: %s", error)


def enqueue_upload_outbox(database, *, job_id: str, payload: dict[str, Any]) -> bool:
    collection = _collection(database)
    if collection is None:
        return False

    ensure_upload_outbox_indexes(database)
    now = datetime.now(timezone.utc)
    document = {
        "job_id": job_id,
        "payload": payload,
        "status": "pending",
        "attempts": 0,
        "last_error": None,
        "created_at": now,
        "updated_at": now,
        "sent_at": None,
    }
    try:
        collection.insert_one(document)
        return True
    except Exception as error:
        logger.warning("Upload outbox enqueue failed job_id=%s: %s", job_id, error)
        return False


def claim_pending_upload_outbox(database, *, limit: int = 20) -> list[dict[str, Any]]:
    collection = _collection(database)
    if collection is None:
        return []

    now = datetime.now(timezone.utc)
    claimed: list[dict[str, Any]] = []
    cursor = collection.find(
        {
            "status": "pending",
            "attempts": {"$lt": MAX_UPLOAD_OUTBOX_ATTEMPTS},
        },
        {"_id": 0},
    ).sort("updated_at", 1).limit(limit)

    for entry in cursor:
        updated = collection.find_one_and_update(
            {"job_id": entry["job_id"], "status": "pending"},
            {
                "$set": {"status": "processing", "updated_at": now},
                "$inc": {"attempts": 1},
            },
            return_document=True,
            projection={"_id": 0},
        )
        if updated:
            claimed.append(updated)
    return claimed


def mark_upload_outbox_sent(
    database, job_id: str, *, correlation_id: str | None = None
) -> None:
    collection = _collection(database)
    if collection is None:
        return
    now = datetime.now(timezone.utc)
    update: dict[str, Any] = {
        "status": "sent",
        "updated_at": now,
        "sent_at": now,
        "last_error": None,
    }
    if correlation_id:
        update["correlation_id"] = correlation_id
    collection.update_one(
        {"job_id": job_id},
        {"$set": update},
    )


def mark_upload_outbox_pending(database, job_id: str, error: str) -> None:
    collection = _collection(database)
    if collection is None:
        return
    now = datetime.now(timezone.utc)
    collection.update_one(
        {"job_id": job_id},
        {"$set": {"status": "pending", "updated_at": now, "last_error": error[:500]}},
    )


def mark_upload_outbox_failed(database, job_id: str, error: str) -> None:
    collection = _collection(database)
    if collection is None:
        return
    now = datetime.now(timezone.utc)
    collection.update_one(
        {"job_id": job_id},
        {
            "$set": {
                "status": "failed",
                "updated_at": now,
                "last_error": error[:500],
            }
        },
    )
