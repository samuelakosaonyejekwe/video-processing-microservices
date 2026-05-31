"""Remove S3 video uploads that have no matching MongoDB job record."""

import logging

from app.database.job_repository import get_job
from app.database.mongo_client import close_mongo_client, get_database
from shared.storage.buckets import video_bucket_name
from shared.storage.s3_client import create_s3_client

logger = logging.getLogger(__name__)


def _list_upload_job_ids(client, bucket: str) -> set[str]:
    prefix = "uploads/videos/"
    job_ids: set[str] = set()
    paginator = client.get_paginator("list_objects_v2")

    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for item in page.get("Contents", []):
            key = item["Key"]
            parts = key.split("/")
            if len(parts) >= 3:
                job_ids.add(parts[2])

    return job_ids


def run_cleanup() -> int:
    bucket = video_bucket_name()
    if not bucket:
        logger.error("Video bucket is not configured")
        return 1

    if get_database() is None:
        logger.error("MongoDB is unavailable")
        return 1

    client = create_s3_client()
    removed = 0

    for job_id in _list_upload_job_ids(client, bucket):
        if get_job(job_id):
            continue

        orphan_prefix = f"uploads/videos/{job_id}/"
        paginator = client.get_paginator("list_objects_v2")
        for page in paginator.paginate(Bucket=bucket, Prefix=orphan_prefix):
            for item in page.get("Contents", []):
                client.delete_object(Bucket=bucket, Key=item["Key"])
                removed += 1
                logger.info("Removed orphan object key=%s", item["Key"])

    close_mongo_client()
    logger.info("Cleanup complete removed_objects=%s", removed)
    return 0


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    raise SystemExit(run_cleanup())
