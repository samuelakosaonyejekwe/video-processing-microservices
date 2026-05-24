def validate_video_extension(filename: str):

    allowed_extensions = [
        ".mp4",
        ".mov",
        ".avi",
        ".mkv"
    ]

    return filename.lower().endswith(
        tuple(allowed_extensions)
    )