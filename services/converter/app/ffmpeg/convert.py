import os

from pathlib import Path

from app.ffmpeg.ffmpeg_utils import (
    run_ffmpeg_command
)


def convert_video_to_audio(
    input_file_path: str,
    processing_dir: str
):

    input_filename = Path(
        input_file_path
    ).stem

    output_filename = (
        f"{input_filename}.mp3"
    )

    output_path = os.path.join(
        processing_dir,
        output_filename
    )

    command = [
        "ffmpeg",
        "-i",
        input_file_path,
        "-vn",
        "-ar",
        "44100",
        "-ac",
        "2",
        "-b:a",
        "192k",
        output_path
    ]

    run_ffmpeg_command(command)

    return output_path