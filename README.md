# VoiceBlogger

Turn any voice recording into a polished blog post and Instagram captions — entirely offline, using local AI. No API keys, no cloud, no cost per run.

Available on **Apple Silicon (M-series Mac)** and as a native **iOS app**. The transcription layer uses [mlx-whisper](https://github.com/ml-explore/mlx-examples/tree/main/whisper), which requires MLX and will not run on Intel Macs, Linux, or Windows.

(Don't worry, other platforms are coming sometime in the future)

---

## How it works

1. **Transcribe** — `mlx-whisper` (Whisper large-v3) converts your audio to text. Pass `--task translate` to get English output from any language, or `--task transcribe` to keep the original language.
2. **Polish** — an Ollama LLM cleans up grammar and formats the transcript as a readable blog post.
3. **Instagram captions** — the same model generates 3–5 ready-to-post captions with hashtags.

All three outputs are saved as files next to your audio.

## iOS app

The iOS app is a SwiftUI companion to the Mac workflow. On first launch it downloads the required on-device models once, then runs fully offline.

What it includes:

- One-tap recording with live waveform feedback
- Automatic transcription after you stop recording
- Blog generation and Instagram caption views
- A history screen for past posts stored locally on device
- Built-in model download and retry handling

The app lives under [iOS App/VoiceBlogger](iOS%20App/VoiceBlogger).

---

## Prerequisites

### 1. Apple Silicon Mac

MLX only runs on M-series chips (M1/M2/M3/M4).

### 2. Python dependencies

```bash
pip install -r requirements.txt
```

On first run, `mlx-whisper` will automatically download the Whisper large-v3 model (~3 GB).

### 3. Ollama

Install [Ollama](https://ollama.com) and pull a model:

```bash
# Install Ollama, then:
ollama pull gemma4:e4b   # default model (~9.6 GB)

# Or use any other model you have installed:
ollama list
```

Ollama must be running before you use this tool (`ollama serve` or the Ollama desktop app).

### iOS app setup

The iOS app manages its own on-device model downloads on first launch, so there is no separate API-key or cloud setup. Once the models are present, the app works offline for recording, transcription, blog generation, and caption creation.

---

## Usage

```bash
python Transcribe_and_blog.py <audio_file> [options]
```

### Options

| Flag | Default | Description |
|---|---|---|
| `--language` | `hi` | Source language ([ISO 639-1](https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes) code, e.g. `en`, `hi`, `es`, `fr`) |
| `--task` | `translate` | `translate` → English output; `transcribe` → keeps source language |
| `--model` | `gemma4:e4b` | Ollama model name (run `ollama list` to see what you have) |
| `--no-instagram` | off | Skip Instagram caption generation |

### Examples

```bash
# Hindi audio → English blog + Instagram captions (defaults)
python Transcribe_and_blog.py my_recording.m4a

# English audio → English blog, no Instagram captions
python Transcribe_and_blog.py podcast.m4a --language en --task transcribe --no-instagram

# Spanish audio → English blog using a different model
python Transcribe_and_blog.py entrevista.mp3 --language es --task translate --model qwen2.5:14b
```

### Project layout

```
voiceblogger/
├── Raw_Data/               # drop audio files here; raw transcripts saved here too
│   └── recording.m4a
├── blog/                   # polished blog posts (auto-created)
│   └── recording_blog.md
├── insta/                  # Instagram captions (auto-created)
│   └── recording_instagram.md
├── iOS App/VoiceBlogger/   # native SwiftUI iOS app
└── Transcribe_and_blog.py
```

### Output files

Given `Raw_Data/recording.m4a`, three files are produced:

| File | Contents |
|---|---|
| `Raw_Data/recording_raw.txt` | Raw Whisper transcript |
| `blog/recording_blog.md` | Polished blog post (Markdown) |
| `insta/recording_instagram.md` | Instagram captions with hashtags |

---

## Supported audio formats

Any format supported by Whisper: `.m4a`, `.mp3`, `.wav`, `.mp4`, `.ogg`, `.flac`, and more.

---

## License

Apache License 2.0 — see [LICENSE](LICENSE).
