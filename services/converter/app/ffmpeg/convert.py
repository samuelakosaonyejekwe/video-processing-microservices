import os
from app.ffmpeg.ffmpeg_utils import run_ffmpeg_command


def convert_video_to_audio(input_file: str):

    output_file = os.path.splitext(input_file)[0] + ".mp3"

    output_path = f"output/{output_file}"

    command = [
        "ffmpeg",
        "-i",
        f"uploads/{input_file}",
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