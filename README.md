<div align="center">

# 🎙️ Voice Blogger

**Turn your voice into polished blog posts — entirely on-device.**

No cloud. No API keys. No cost per run. Just private, local AI.

[![Download on the App Store](https://img.shields.io/badge/Download_on_the-App_Store-0D96F6?style=for-the-badge&logo=apple&logoColor=white)](https://apps.apple.com/us/app/voice-blogger/id6777303710)
&nbsp;
[![iOS 17+](https://img.shields.io/badge/iOS-17%2B-black?style=for-the-badge&logo=apple)](https://apps.apple.com/us/app/voice-blogger/id6777303710)
&nbsp;
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-green?style=for-the-badge)](LICENSE)

</div>

---

## What is Voice Blogger?

Voice Blogger lets you record a voice note and walk away with a fully written, formatted blog post — along with ready-to-post LinkedIn and Instagram captions. Everything runs locally on your iPhone using on-device AI models. No account required, no internet needed after setup.

```
Record your voice  →  Transcribe  →  Polish into a blog post  →  Export to LinkedIn / Instagram
```

---

## Features

| | Feature | Details |
|---|---|---|
| 🎙️ | **One-tap recording** | Live waveform visualizer, background recording support |
| 📝 | **On-device transcription** | Powered by WhisperKit (OpenAI Whisper on-device) |
| 🤖 | **Local LLM blog generation** | Qwen 2.5 model runs fully offline — your words never leave your device |
| 📱 | **LinkedIn & Instagram captions** | Auto-generates platform-native captions with hashtags |
| 🗂️ | **Post history** | All recordings and generated content saved locally |
| 🔒 | **100% private** | No cloud, no accounts, no telemetry |
| ⚡ | **Streaming generation** | Watch your blog post write itself in real time |

---

## Getting Started

### iOS App (Recommended)

1. **[Download Voice Blogger from the App Store](https://apps.apple.com/us/app/voice-blogger/id6777303710)**
2. On first launch, tap **Download Models** — this takes a few minutes on Wi-Fi
3. Tap the microphone, start talking
4. Stop recording — transcription begins automatically
5. Tap **Generate Blog** and watch it write

That's it. No signup, no API key, no cloud.

---

## CLI Tool (Mac Only)

A Python command-line version is also included for **Apple Silicon Macs** (M1/M2/M3/M4). It uses [mlx-whisper](https://github.com/ml-explore/mlx-examples/tree/main/whisper) and requires [Ollama](https://ollama.com).

> **Note:** The CLI requires Apple Silicon. MLX does not run on Intel Macs, Linux, or Windows.

### Setup

```bash
# 1. Install Python dependencies
pip install -r requirements.txt

# 2. Install Ollama and pull a model
ollama pull gemma4:e4b   # default
```

### Usage

```bash
python Transcribe_and_blog.py <audio_file> [options]
```

| Flag | Default | Description |
|---|---|---|
| `--language` | `en` | Source language (ISO 639-1 code: `en`, `hi`, `es`, `fr` …) |
| `--task` | `translate` | `translate` → English output · `transcribe` → keeps source language |
| `--model` | `gemma4:e4b` | Ollama model name (run `ollama list` to see installed models) |
| `--no-instagram` | off | Skip Instagram caption generation |

### Examples

```bash
# Hindi audio → English blog + Instagram captions (defaults)
python Transcribe_and_blog.py my_recording.m4a

# English podcast, no Instagram captions
python Transcribe_and_blog.py podcast.m4a --language en --task transcribe --no-instagram

# Spanish audio → English blog with a different model
python Transcribe_and_blog.py entrevista.mp3 --language es --task translate --model qwen2.5:14b
```

### Output

Given `Raw_Data/recording.m4a`, three files are produced:

| File | Contents |
|---|---|
| `Raw_Data/recording_raw.txt` | Raw Whisper transcript |
| `blog/recording_blog.md` | Polished blog post (Markdown) |
| `insta/recording_instagram.md` | Instagram captions with hashtags |

---

## Project Structure

```
voiceblogger/
├── iOS App/VoiceBlogger/       # Native SwiftUI iOS app ← main product
│   └── VoiceBlogger/
│       ├── Models/             # Data models and migration
│       ├── Services/           # Audio, transcription, LLM
│       ├── Views/              # SwiftUI screens
│       └── Utilities/          # Prompts, blog generation
├── Android-App/                # Android companion (beta)
├── cliTools/                   # Python CLI scripts
│   └── Transcribe_and_blog.py
├── Raw_Data/                   # Drop audio files here (CLI)
├── blog/                       # Generated blog posts (CLI)
└── insta/                      # Generated captions (CLI)
```

---

## Privacy

Voice Blogger is designed from the ground up for privacy:

- **No account required** — ever
- **No internet required** after first-time model download
- **No analytics or telemetry** collected
- **All audio and text stays on your device**
- Models run on the **Neural Engine** — fast, efficient, private

See [PrivacyPolicy.md](PrivacyPolicy.md) for the full privacy policy.

---

## Requirements

| Platform | Requirement |
|---|---|
| **iOS App** | iPhone with iOS 17+, ~2 GB free storage (for models) |
| **CLI Tool** | Apple Silicon Mac (M1/M2/M3/M4), Python 3.10+, Ollama |
| **Android App** | Android 12+ (beta) |

---

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) first.

---

## License

[Apache License 2.0](LICENSE) — free to use, modify, and distribute.

---

<div align="center">

Made with ❤️ for people who think better out loud.

[![Download on the App Store](https://img.shields.io/badge/Download_on_the-App_Store-0D96F6?style=for-the-badge&logo=apple&logoColor=white)](https://apps.apple.com/us/app/voice-blogger/id6777303710)

</div>
