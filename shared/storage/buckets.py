import os


def first_env(*names: str, default: str = "") -> str:
    for name in names:
        value = os.getenv(name)
        if value and value.strip():
            return value.strip()
    return default


def video_bucket_name() -> str:
    return first_env(
        "AWS_S3_VIDEO_BUCKET",
        "AWS_S3_BUCKET",
        "S3_UPLOAD_BUCKET",
        "S3_BUCKET_NAME",
        default="",
    )


def audio_bucket_name() -> str:
    return first_env(
        "S3_AUDIO_BUCKET",
        "AWS_S3_AUDIO_BUCKET",
        default=video_bucket_name(),
    )
