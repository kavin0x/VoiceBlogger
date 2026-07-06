#!/usr/bin/env python3
"""
Transcribe audio with mlx_whisper, polish into a blog post, and generate
Instagram captions — all using local AI (no cloud, no API keys).

Requires Apple Silicon (MLX). Ollama must be running locally.

Usage:
    python Transcribe_and_blog.py <audio_file> [options]

Examples:
    python Transcribe_and_blog.py recording.m4a
    python Transcribe_and_blog.py recording.m4a --language en --task transcribe
    python Transcribe_and_blog.py recording.m4a --language hi --task translate --model gemma4:e4b
    python Transcribe_and_blog.py recording.m4a --no-instagram
    python Transcribe_and_blog.py recording.m4a --transcribe-only
"""

import sys
import json
import argparse
import threading
import requests
from pathlib import Path
from tqdm import tqdm
import mlx_whisper

WHISPER_MODEL = "mlx-community/whisper-large-v3-mlx"
OLLAMA_URL = "http://localhost:11434/api/generate"

PROJECT_ROOT = Path(__file__).resolve().parent
RAW_DATA_DIR = PROJECT_ROOT / "Raw_Data"
BLOG_DIR     = PROJECT_ROOT / "blog"
INSTA_DIR    = PROJECT_ROOT / "insta"


# ── Step 1: Transcribe ────────────────────────────────────────────────────────

def transcribe(audio_path: str, language: str, task: str) -> str:
    result_box: list = [None]
    error_box: list[Exception | None] = [None]

    def _run():
        try:
            result_box[0] = mlx_whisper.transcribe(
                audio_path,
                path_or_hf_repo=WHISPER_MODEL,
                language=language,
                task=task,
                verbose=True,
            )
        except Exception as e:
            error_box[0] = e

    print()
    t = threading.Thread(target=_run, daemon=True)
    t.start()

    with tqdm(
        total=None,
        desc="  Transcribing",
        bar_format="{desc}: {elapsed} elapsed {postfix}",
        dynamic_ncols=True,
    ) as pbar:
        while t.is_alive():
            t.join(timeout=0.5)
            pbar.update(0)
        pbar.bar_format = "{desc}: ✓ done in {elapsed}"
        pbar.update(0)

    if error_box[0]:
        raise error_box[0]

    return result_box[0]["text"].strip()


# ── Step 2: Save raw ──────────────────────────────────────────────────────────

def save_raw(text: str, out_path: Path) -> None:
    with tqdm(total=1, desc="  Saving raw transcript",
              bar_format="{desc}: {n_fmt}/{total_fmt} {bar}") as pbar:
        out_path.write_text(text, encoding="utf-8")
        pbar.update(1)
    print(f"     → {out_path}")


# ── Ollama streaming helper ───────────────────────────────────────────────────

def _ollama_generate(model: str, prompt: str, desc: str) -> str:
    print(f"\n  {desc} with {model} (streaming):\n")
    print("  " + "─" * 56)

    chunks = []

    with tqdm(
        total=None,
        desc="  Tokens",
        unit=" tok",
        bar_format="{desc}: {n_fmt}{unit} | {elapsed} elapsed",
        dynamic_ncols=True,
        leave=True,
        position=0,
    ) as pbar:
        resp = requests.post(
            OLLAMA_URL,
            json={"model": model, "prompt": prompt, "stream": True},
            stream=True,
            timeout=300,
        )
        resp.raise_for_status()

        for line in resp.iter_lines():
            if not line:
                continue
            data = json.loads(line)
            token = data.get("response", "")
            if token:
                tqdm.write(token, end="", nolock=True)
                chunks.append(token)
                pbar.update(1)
            if data.get("done"):
                break

    print("\n  " + "─" * 56)
    return "".join(chunks).strip()


# ── Step 3: Polish into blog post ─────────────────────────────────────────────

def polish_with_ollama(raw_text: str, model: str, language: str, task: str) -> str:
    if task == "translate":
        source_desc = f"a raw English translation of a {language} audio recording"
    else:
        source_desc = "a raw audio transcript"

    prompt = f"""You are a blog editor. Below is {source_desc}.

Your job:
1. Fix minor grammar, punctuation, and flow issues
2. Format it as a clean, readable blog post with a title and paragraphs
3. Do NOT add new information, opinions, or change the meaning
4. Do NOT make it longer than necessary — preserve the original voice
5. Keep cultural references, names, and places exactly as they are

Raw transcript:
{raw_text}

Output only the final blog post, nothing else."""

    return _ollama_generate(model, prompt, "Polishing blog post")


# ── Step 4: Generate Instagram captions ──────────────────────────────────────

def generate_instagram_posts(blog_text: str, model: str) -> str:
    prompt = f"""You are a social media copywriter. Below is a blog post.

Your job:
1. Write 3 to 5 short Instagram captions based on the blog post content
2. Each caption must be under 150 words, engaging, and conversational
3. End each caption with 5–8 relevant hashtags
4. Separate captions with a line containing only "---"
5. Do NOT add new information or change the meaning
6. Preserve cultural references, names, and places exactly as they are

Blog post:
{blog_text}

Output only the captions, nothing else."""

    return _ollama_generate(model, prompt, "Generating Instagram captions")


# ── Main ──────────────────────────────────────────────────────────────────────

def parse_args():
    parser = argparse.ArgumentParser(
        description="Transcribe audio and polish it into a blog post using local AI."
    )
    parser.add_argument("audio_file", help="Path to the audio file (e.g. recording.m4a)")
    parser.add_argument(
        "--language", default="hi",
        help="Source language code for Whisper (default: hi). "
             "Use ISO 639-1 codes, e.g. en, hi, es, fr.",
    )
    parser.add_argument(
        "--task", default="translate", choices=["transcribe", "translate"],
        help="Whisper task: 'transcribe' keeps original language, "
             "'translate' converts to English (default: translate).",
    )
    parser.add_argument(
        "--model", default="gemma4:e4b",
        help="Ollama model for blog polishing and Instagram captions (default: gemma4:e4b). "
             "Run 'ollama list' to see available models.",
    )
    parser.add_argument(
        "--no-instagram", action="store_true",
        help="Skip Instagram caption generation.",
    )
    parser.add_argument(
        "--transcribe-only", action="store_true",
        help="Only transcribe and save the raw transcript; skip blog and Instagram generation.",
    )
    return parser.parse_args()


def main():
    args = parse_args()

    audio_file = Path(args.audio_file).resolve()
    if not audio_file.exists():
        print(f"Error: file not found: {audio_file}", file=sys.stderr)
        sys.exit(1)

    stem = audio_file.stem
    for d in (RAW_DATA_DIR, BLOG_DIR, INSTA_DIR):
        d.mkdir(exist_ok=True)

    raw_path       = RAW_DATA_DIR / f"{stem}_raw.txt"
    blog_path      = BLOG_DIR     / f"{stem}_blog.md"
    instagram_path = INSTA_DIR    / f"{stem}_instagram.md"

    transcribe_only = args.transcribe_only
    skip_instagram = args.no_instagram
    steps = ["Transcribe", "Save raw"]
    if not transcribe_only:
        steps.append("Polish + save blog")
        if not skip_instagram:
            steps.append("Generate Instagram captions")

    overall = tqdm(
        total=len(steps),
        desc="Overall",
        bar_format="{desc}: {n_fmt}/{total_fmt} [{bar}] {postfix}",
        dynamic_ncols=True,
        position=1,
    )

    overall.set_postfix_str("transcribing...")
    raw_text = transcribe(args.audio_file, args.language, args.task)
    overall.update(1)

    overall.set_postfix_str("saving raw...")
    save_raw(raw_text, raw_path)
    overall.update(1)

    if not transcribe_only:
        overall.set_postfix_str("polishing...")
        blog_text = polish_with_ollama(raw_text, args.model, args.language, args.task)
        blog_path.write_text(blog_text, encoding="utf-8")
        overall.update(1)

        if not skip_instagram:
            overall.set_postfix_str("generating instagram captions...")
            instagram_text = generate_instagram_posts(blog_text, args.model)
            instagram_path.write_text(instagram_text, encoding="utf-8")
            overall.update(1)

    overall.set_postfix_str("done ✓")
    overall.close()

    print(f"\n  ✓ Raw transcript  → {raw_path}  ({raw_path.stat().st_size:,} bytes)")
    if not transcribe_only:
        print(f"  ✓ Blog post       → {blog_path}  ({blog_path.stat().st_size:,} bytes)")
        if not skip_instagram:
            print(f"  ✓ Instagram posts → {instagram_path}  ({instagram_path.stat().st_size:,} bytes)")
    print()


if __name__ == "__main__":
    main()
