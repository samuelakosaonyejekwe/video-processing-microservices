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


def _audio_bucket() -> str:
    return os.getenv("S3_AUDIO_BUCKET") or os.getenv("AWS_S3_AUDIO_BUCKET") or ""


def audio_object_key(job_id: str) -> str:
    prefix = os.getenv("S3_AUDIO_OUTPUT_PREFIX", "outputs/audio/").rstrip("/")
    return f"{prefix}/{job_id}.mp3"


def object_exists(bucket: str, object_key: str) -> bool:
    client = create_s3_client()
    try:
        client.head_object(Bucket=bucket, Key=object_key)
        return True
    except ClientError as error:
        if error.response.get("Error", {}).get("Code") in (
            "404",
            "NoSuchKey",
            "NotFound",
        ):
            return False
        raise RuntimeError(f"S3 head_object failed: {error}") from error


def generate_presigned_download_url(
    bucket: str, object_key: str, download_filename: str, expires_in: int = 3600
) -> str:
    client = create_s3_client()
    try:
        return client.generate_presigned_url(
            "get_object",
            Params={
                "Bucket": bucket,
                "Key": object_key,
                "ResponseContentDisposition": (
                    f'attachment; filename="{download_filename}"'
                ),
            },
            ExpiresIn=expires_in,
        )
    except ClientError as error:
        raise RuntimeError(f"S3 presign failed: {error}") from error


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


def delete_object(bucket: str, object_key: str) -> None:
    client = create_s3_client()
    try:
        client.delete_object(Bucket=bucket, Key=object_key)
    except ClientError as error:
        raise RuntimeError(f"S3 delete failed: {error}") from error
