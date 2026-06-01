import os

import time

import shutil

# Clean the same directory the consumer writes to. Fall back through the
# consumer's TEMP_STORAGE_PATH so the two never silently diverge.
TEMP_PROCESSING_DIR = (
    os.getenv("TEMP_PROCESSING_DIR")
    or os.getenv("TEMP_STORAGE_PATH")
    or "/tmp/video-converter"
)


MAX_FILE_AGE_SECONDS = int(os.getenv("TEMP_FILE_MAX_AGE_SECONDS", "3600"))


def cleanup_temp_files():

    current_time = time.time()

    for root, dirs, files in os.walk(TEMP_PROCESSING_DIR):

        for directory in dirs:

            directory_path = os.path.join(root, directory)

            modified_time = os.path.getmtime(directory_path)

            if current_time - modified_time > MAX_FILE_AGE_SECONDS:

                shutil.rmtree(directory_path, ignore_errors=True)


if __name__ == "__main__":

    cleanup_temp_files()
