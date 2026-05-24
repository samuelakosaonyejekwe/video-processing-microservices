import boto3
import os
from botocore.exceptions import ClientError

# ==========================================================
# AWS CONFIGURATION
# ==========================================================

AWS_REGION = os.getenv(
    "AWS_REGION",
    "eu-west-2"
)

UPLOAD_BUCKET = os.getenv(
    "S3_UPLOAD_BUCKET",
    "video-converter-uploads-sam"
)

AUDIO_BUCKET = os.getenv(
    "S3_AUDIO_BUCKET",
    "video-converter-audio-sam"
)

THUMBNAIL_BUCKET = os.getenv(
    "S3_THUMBNAIL_BUCKET",
    "video-converter-thumbnails-sam"
)

# ==========================================================
# S3 CLIENT
# ==========================================================

s3_client = boto3.client(
    "s3",
    region_name=AWS_REGION
)

# ==========================================================
# VIDEO UPLOAD
# ==========================================================

def upload_video_to_s3(
    local_file_path: str,
    s3_filename: str
):

    try:

        s3_client.upload_file(
            local_file_path,
            UPLOAD_BUCKET,
            s3_filename
        )

        s3_url = (
            f"https://{UPLOAD_BUCKET}.s3."
            f"{AWS_REGION}.amazonaws.com/"
            f"{s3_filename}"
        )

        print(
            f"Video uploaded successfully: {s3_url}"
        )

        return s3_url

    except ClientError as error:

        print(
            f"S3 upload error: {error}"
        )

        raise error

# ==========================================================
# AUDIO UPLOAD
# ==========================================================

def upload_audio_to_s3(
    local_file_path: str,
    s3_filename: str
):

    try:

        s3_client.upload_file(
            local_file_path,
            AUDIO_BUCKET,
            s3_filename
        )

        s3_url = (
            f"https://{AUDIO_BUCKET}.s3."
            f"{AWS_REGION}.amazonaws.com/"
            f"{s3_filename}"
        )

        print(
            f"Audio uploaded successfully: {s3_url}"
        )

        return s3_url

    except ClientError as error:

        print(
            f"S3 upload error: {error}"
        )

        raise error

# ==========================================================
# THUMBNAIL UPLOAD
# ==========================================================

def upload_thumbnail_to_s3(
    local_file_path: str,
    s3_filename: str
):

    try:

        s3_client.upload_file(
            local_file_path,
            THUMBNAIL_BUCKET,
            s3_filename
        )

        s3_url = (
            f"https://{THUMBNAIL_BUCKET}.s3."
            f"{AWS_REGION}.amazonaws.com/"
            f"{s3_filename}"
        )

        print(
            f"Thumbnail uploaded successfully: {s3_url}"
        )

        return s3_url

    except ClientError as error:

        print(
            f"S3 upload error: {error}"
        )

        raise error

# ==========================================================
# DOWNLOAD VIDEO FROM S3
# ==========================================================

def download_video_from_s3(
    s3_filename: str,
    local_download_path: str
):

    try:

        s3_client.download_file(
            UPLOAD_BUCKET,
            s3_filename,
            local_download_path
        )

        print(
            f"Video downloaded successfully: "
            f"{local_download_path}"
        )

        return local_download_path

    except ClientError as error:

        print(
            f"S3 download error: {error}"
        )

        raise error

# ==========================================================
# DELETE FILE FROM S3
# ==========================================================

def delete_file_from_s3(
    bucket_name: str,
    s3_filename: str
):

    try:

        s3_client.delete_object(
            Bucket=bucket_name,
            Key=s3_filename
        )

        print(
            f"Deleted file from S3: {s3_filename}"
        )

    except ClientError as error:

        print(
            f"S3 delete error: {error}"
        )

        raise error