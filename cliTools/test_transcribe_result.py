import threading
import time
import unittest

from transcribe_result import (
    TranscriptionResultError,
    transcript_text,
    wait_for_thread,
)


class TranscriptTextTests(unittest.TestCase):
    def test_reads_text(self):
        self.assertEqual(transcript_text({"text": "  hello world  "}), "hello world")

    def test_missing_text_key_raises(self):
        with self.assertRaises(TranscriptionResultError):
            transcript_text({"segments": []})

    def test_non_dict_raises(self):
        with self.assertRaises(TranscriptionResultError):
            transcript_text(None)

    def test_non_string_text_raises(self):
        with self.assertRaises(TranscriptionResultError):
            transcript_text({"text": 12})

    def test_hung_worker_times_out(self):
        started = threading.Event()

        def hang():
            started.set()
            time.sleep(5)

        worker = threading.Thread(target=hang, daemon=True)
        worker.start()
        self.assertTrue(started.wait(1))
        with self.assertRaises(TimeoutError):
            wait_for_thread(worker, timeout=0.2, join_slice=0.05)


if __name__ == "__main__":
    unittest.main()
