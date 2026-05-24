import os
import shutil

UPLOAD_FOLDER = "uploads"
OUTPUT_FOLDER = "output"


def save_uploaded_file(source_path: str, filename: str):

    destination = os.path.join(
        UPLOAD_FOLDER,
        filename
    )

    shutil.copy(source_path, destination)

    return destination


def save_converted_file(source_path: str, filename: str):

    destination = os.path.join(
        OUTPUT_FOLDER,
        filename
    )

    shutil.copy(source_path, destination)

    return destination