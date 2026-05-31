import os

from botocore.exceptions import ClientError

from shared.storage.s3_client import create_s3_client

# ==========================================================
# ENVIRONMENT VARIABLES
# ==========================================================

AWS_REGION = os.getenv("AWS_REGION")

S3_UPLOAD_BUCKET = os.getenv("S3_UPLOAD_BUCKET")

S3_AUDIO_BUCKET = os.getenv("S3_AUDIO_BUCKET")

S3_THUMBNAIL_BUCKET = os.getenv("S3_THUMBNAIL_BUCKET")

# ==========================================================
# VALIDATION
# ==========================================================

REQUIRED_ENV_VARS = {
    "AWS_REGION": AWS_REGION,
    "S3_UPLOAD_BUCKET": S3_UPLOAD_BUCKET,
    "S3_AUDIO_BUCKET": S3_AUDIO_BUCKET,
    "S3_THUMBNAIL_BUCKET": S3_THUMBNAIL_BUCKET,
}

missing_env_vars = [key for key, value in REQUIRED_ENV_VARS.items() if not value]

if missing_env_vars:

    raise EnvironmentError(
        "Missing required environment variables: " f"{', '.join(missing_env_vars)}"
    )

# ==========================================================
# S3 CLIENT
# ==========================================================

s3_client = create_s3_client()

# ==========================================================
# GENERIC S3 UPLOAD
# ==========================================================


def upload_file_to_s3(
    local_file_path: str,
    bucket_name: str,
    object_key: str,
    content_type: str | None = None,
):

    try:

        extra_args = {}

        if content_type:

            extra_args["ContentType"] = content_type

        if extra_args:

            s3_client.upload_file(
                local_file_path, bucket_name, object_key, ExtraArgs=extra_args
            )

        else:

            s3_client.upload_file(local_file_path, bucket_name, object_key)

        s3_url = (
            f"https://{bucket_name}.s3." f"{AWS_REGION}.amazonaws.com/" f"{object_key}"
        )

        print(f"S3 upload successful: {s3_url}")

        return s3_url

    except ClientError as error:

        print(f"S3 upload error: {error}")

        raise error


# ==========================================================
# GENERIC S3 DOWNLOAD
# ==========================================================


def download_file_from_s3(bucket_name: str, object_key: str, local_download_path: str):

    try:

        s3_client.download_file(bucket_name, object_key, local_download_path)

        print("S3 download successful: " f"{local_download_path}")

        return local_download_path

    except ClientError as error:

        print(f"S3 download error: {error}")

        raise error


# ==========================================================
# GENERIC S3 DELETE
# ==========================================================


def delete_s3_object(bucket_name: str, object_key: str):

    try:

        s3_client.delete_object(Bucket=bucket_name, Key=object_key)

        print("S3 delete successful: " f"{object_key}")

    except ClientError as error:

        print(f"S3 delete error: {error}")

        raise error


# ==========================================================
# VIDEO HELPERS
# ==========================================================


def upload_video_to_s3(local_file_path: str, object_key: str):

    return upload_file_to_s3(
        local_file_path=local_file_path,
        bucket_name=S3_UPLOAD_BUCKET,
        object_key=object_key,
        content_type="video/mp4",
    )


def download_video_from_s3(object_key: str, local_download_path: str):

    return download_file_from_s3(
        bucket_name=S3_UPLOAD_BUCKET,
        object_key=object_key,
        local_download_path=local_download_path,
    )


# ==========================================================
# AUDIO HELPERS
# ==========================================================


def upload_audio_to_s3(local_file_path: str, object_key: str):

    return upload_file_to_s3(
        local_file_path=local_file_path,
        bucket_name=S3_AUDIO_BUCKET,
        object_key=object_key,
        content_type="audio/mpeg",
    )


# ==========================================================
# THUMBNAIL HELPERS
# ==========================================================


def upload_thumbnail_to_s3(local_file_path: str, object_key: str):

    return upload_file_to_s3(
        local_file_path=local_file_path,
        bucket_name=S3_THUMBNAIL_BUCKET,
        object_key=object_key,
        content_type="image/jpeg",
    )
