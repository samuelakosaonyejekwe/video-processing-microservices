import os

ALLOWED_VIDEO_EXTENSIONS = (".mp4", ".mov", ".avi", ".mkv", ".webm")

ALLOWED_VIDEO_CONTENT_TYPES = (
    "video/mp4",
    "video/quicktime",
    "video/x-msvideo",
    "video/x-matroska",
    "video/webm",
    "application/octet-stream",
)


def sanitize_filename(filename: str) -> str:
    if not filename or not filename.strip():
        raise ValueError("Filename is required")

    base = os.path.basename(filename.strip())
    if not base or base in (".", "..") or ".." in base:
        raise ValueError("Invalid filename")

    return base


def validate_video_extension(filename: str) -> bool:
    return filename.lower().endswith(ALLOWED_VIDEO_EXTENSIONS)


def get_max_upload_size_bytes() -> int:
    megabytes = int(os.getenv("MAX_VIDEO_UPLOAD_SIZE_MB", "500"))
    return megabytes * 1024 * 1024


def validate_upload_size(size: int) -> None:
    maximum = get_max_upload_size_bytes()
    if size > maximum:
        limit_mb = maximum // (1024 * 1024)
        raise ValueError(f"File exceeds maximum size of {limit_mb} MB")


def validate_content_type(content_type: str | None) -> bool:
    if not content_type:
        return True

    base_type = content_type.split(";")[0].strip().lower()
    return base_type.startswith("video/") or base_type in ALLOWED_VIDEO_CONTENT_TYPES
