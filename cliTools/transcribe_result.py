"""Pure helpers for the local transcribe script. No model imports."""

from __future__ import annotations

import time
from threading import Thread


class TranscriptionResultError(RuntimeError):
    """mlx_whisper returned a result that does not contain transcript text."""


# A hung Whisper job must not keep the process alive forever.
# An hour covers a long recording on a large local model.
TRANSCRIBE_TIMEOUT_SECONDS = 60 * 60


def transcript_text(result: object) -> str:
    if not isinstance(result, dict) or "text" not in result:
        raise TranscriptionResultError(
            "Transcription finished without a text field."
        )
    text = result["text"]
    if not isinstance(text, str):
        raise TranscriptionResultError("Transcription text field was not a string.")
    return text.strip()


def wait_for_thread(thread: Thread, timeout: float, join_slice: float = 0.5, on_wait=None) -> None:
    """Wait until the worker finishes, or raise if it is still alive after timeout."""
    deadline = time.monotonic() + timeout
    while thread.is_alive():
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError(
                f"Transcription exceeded {int(timeout)} seconds and was abandoned."
            )
        thread.join(timeout=min(join_slice, remaining))
        if on_wait is not None:
            on_wait()
