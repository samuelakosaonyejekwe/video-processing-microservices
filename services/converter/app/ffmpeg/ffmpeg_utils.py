import os
import subprocess


def run_ffmpeg_command(command, timeout_seconds: int | None = None):
    # Always bound execution time so a malformed/huge input cannot hang the
    # process indefinitely.
    if timeout_seconds is None:
        timeout_seconds = int(os.getenv("MAX_CONVERSION_TIMEOUT_SECONDS", "90"))

    process = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout_seconds,
    )

    if process.returncode != 0:
        # Avoid leaking full ffmpeg stderr (may contain internal paths) to the
        # caller; keep only a short tail for diagnostics.
        stderr_tail = process.stderr.decode(errors="replace")[-500:]
        raise RuntimeError(f"ffmpeg failed (exit {process.returncode}): {stderr_tail}")

    return process.stdout.decode(errors="replace")
