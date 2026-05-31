import logging

from app.database.mongo_client import get_database
from app.queue.producer import get_gateway_producer
from shared.outbox.upload_outbox import (
    MAX_UPLOAD_OUTBOX_ATTEMPTS,
    claim_pending_upload_outbox,
    mark_upload_outbox_failed,
    mark_upload_outbox_pending,
    mark_upload_outbox_sent,
)

logger = logging.getLogger(__name__)


def _publish_outbox_entry(entry: dict) -> str:
    job_id = entry.get("job_id")
    payload = entry.get("payload") or {}
    return get_gateway_producer().publish_video_upload_event(
        job_id=payload.get("job_id", job_id),
        user_id=payload.get("user_id"),
        filename=payload.get("filename"),
        s3_key=payload.get("s3_key"),
        content_type=payload.get("content_type"),
    )


def relay_upload_outbox_for_job(job_id: str) -> str:
    database = get_database()
    if database is None:
        raise RuntimeError("MongoDB unavailable for upload outbox")

    existing = database.upload_outbox.find_one({"job_id": job_id}, {"_id": 0})
    if existing is None:
        raise RuntimeError(f"Upload outbox entry missing for job_id={job_id}")

    if existing.get("status") == "sent":
        stored = existing.get("correlation_id")
        if stored:
            return stored
        payload = existing.get("payload") or {}
        return payload.get("job_id", job_id)

    entries = claim_pending_upload_outbox(database, limit=50)
    target = next((entry for entry in entries if entry.get("job_id") == job_id), None)
    if target is None:
        raise RuntimeError(f"Upload outbox entry not claimable for job_id={job_id}")

    try:
        correlation_id = _publish_outbox_entry(target)
        mark_upload_outbox_sent(database, job_id, correlation_id=correlation_id)
        logger.info("Upload outbox relayed job_id=%s", job_id)
        return correlation_id
    except Exception as error:
        attempts = int(target.get("attempts", 1))
        message = str(error)
        if attempts >= MAX_UPLOAD_OUTBOX_ATTEMPTS:
            mark_upload_outbox_failed(database, job_id, message)
        else:
            mark_upload_outbox_pending(database, job_id, message)
        raise


def relay_upload_outbox(*, limit: int = 20) -> int:
    database = get_database()
    if database is None:
        return 0

    relayed = 0
    for entry in claim_pending_upload_outbox(database, limit=limit):
        job_id = entry.get("job_id")
        try:
            correlation_id = _publish_outbox_entry(entry)
            mark_upload_outbox_sent(database, job_id, correlation_id=correlation_id)
            relayed += 1
            logger.info("Upload outbox relayed job_id=%s", job_id)
        except Exception as error:
            attempts = int(entry.get("attempts", 1))
            message = str(error)
            if attempts >= MAX_UPLOAD_OUTBOX_ATTEMPTS:
                mark_upload_outbox_failed(database, job_id, message)
                logger.error(
                    "Upload outbox permanently failed job_id=%s: %s",
                    job_id,
                    message,
                )
            else:
                mark_upload_outbox_pending(database, job_id, message)
                logger.warning(
                    "Upload outbox relay retry scheduled job_id=%s: %s",
                    job_id,
                    message,
                )

    return relayed
