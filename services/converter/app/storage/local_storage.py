import os
import shutil


def save_uploaded_file(source_path: str, filename: str):

    destination = os.path.join(filename)

    shutil.copy(source_path, destination)

    return destination


def save_converted_file(source_path: str, filename: str):

    destination = os.path.join(filename)

    shutil.copy(source_path, destination)

    return destination
