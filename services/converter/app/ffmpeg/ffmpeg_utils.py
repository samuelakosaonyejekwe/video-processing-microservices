import subprocess


def run_ffmpeg_command(command):

    process = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )

    if process.returncode != 0:

        raise Exception(
            process.stderr.decode()
        )

    return process.stdout.decode()