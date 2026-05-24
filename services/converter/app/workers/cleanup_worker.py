import os
import time


UPLOAD_FOLDER = "uploads"
OUTPUT_FOLDER = "output"


def cleanup_old_files():

    while True:

        for folder in [UPLOAD_FOLDER, OUTPUT_FOLDER]:

            for filename in os.listdir(folder):

                file_path = os.path.join(folder, filename)

                file_age = time.time() - os.path.getmtime(file_path)

                # Delete files older than 1 hour

                if file_age > 3600:

                    os.remove(file_path)

                    print(f"Deleted old file: {file_path}")

        time.sleep(300)


if __name__ == "__main__":

    cleanup_old_files()