import os

from pathlib import Path

from app.ffmpeg.ffmpeg_utils import run_ffmpeg_command


def convert_video_to_audio(input_file_path: str, processing_dir: str, job_id: str = ""):

    # Derive the output name from a validated job id when available so the
    # output path can't be steered by an attacker-controlled input filename.
    # Fall back to the input stem (basename only) otherwise.
    if job_id and job_id.strip():
        output_filename = f"{Path(job_id.strip()).name}.mp3"
    else:
        output_filename = f"{Path(input_file_path).stem}.mp3"

    output_path = os.path.join(processing_dir, output_filename)

    # Containment check: the resolved output must stay inside processing_dir so
    # a crafted job id / filename can't write outside the processing sandbox.
    real_dir = os.path.realpath(processing_dir)
    real_output = os.path.realpath(output_path)
    if os.path.commonpath([real_dir, real_output]) != real_dir:
        raise ValueError("Output path escapes the processing directory")

    command = [
        "ffmpeg",
        "-y",
        "-i",
        input_file_path,
        "-vn",
        "-ar",
        "44100",
        "-ac",
        "2",
        "-b:a",
        "192k",
        output_path,
    ]

    run_ffmpeg_command(command)

    return output_path
