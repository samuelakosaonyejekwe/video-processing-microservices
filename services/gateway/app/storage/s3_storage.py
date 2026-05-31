import os

from botocore.exceptions import ClientError

from shared.storage.s3_client import create_s3_client


def _video_bucket() -> str:
    return (
        os.getenv("AWS_S3_VIDEO_BUCKET")
        or os.getenv("AWS_S3_BUCKET")
        or os.getenv("S3_UPLOAD_BUCKET")
        or ""
    )


def upload_video_to_s3(local_file_path: str, object_key: str, content_type: str) -> str:
    bucket = _video_bucket()
    if not bucket:
        raise RuntimeError("AWS_S3_VIDEO_BUCKET is not configured")

    client = create_s3_client()
    extra_args = {"ContentType": content_type} if content_type else None

    try:
        if extra_args:
            client.upload_file(
                local_file_path, bucket, object_key, ExtraArgs=extra_args
            )
        else:
            client.upload_file(local_file_path, bucket, object_key)
    except ClientError as error:
        raise RuntimeError(f"S3 upload failed: {error}") from error

    return f"s3://{bucket}/{object_key}"
