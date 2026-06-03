import os
import shutil

from app.config import TEMP_PROCESSING_DIR
from shared.security.upload_validation import sanitize_filename


def _safe_destination(filename: str) -> str:

    # Strip any directory components / traversal and pin the write to a fixed
    # base directory so a caller-supplied name can't escape the sandbox.
    safe_name = sanitize_filename(filename)

    base_dir = os.path.realpath(TEMP_PROCESSING_DIR)
    destination = os.path.realpath(os.path.join(base_dir, safe_name))

    if os.path.commonpath([base_dir, destination]) != base_dir:
        raise ValueError("Invalid filename")

    os.makedirs(base_dir, exist_ok=True)

    return destination


def save_uploaded_file(source_path: str, filename: str):

    destination = _safe_destination(filename)

    shutil.copy(source_path, destination)

    return destination


def save_converted_file(source_path: str, filename: str):

    destination = _safe_destination(filename)

    shutil.copy(source_path, destination)

    return destination
