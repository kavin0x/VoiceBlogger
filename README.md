# Voice Blogger

Speak a rough idea. Get a blog post, notes, or social captions — on your iPhone, offline, no account.

**[App Store](https://apps.apple.com/us/app/voice-blogger/id6777303710)** · free · open source

## Why I built this

I lose ideas when I only have time to talk them out, not sit down and write. Most voice tools upload your audio. I didn’t want that, so I built an app that does the whole job on the phone.

## Cloud tools vs this

| | Typical cloud tools | Voice Blogger |
| --- | --- | --- |
| Audio / text | Sent to a server | Stays on your device |
| Cost | Subscription or per-token | Free after download |
| After setup | Needs internet | Works offline |
| Account | Usually required | None |

## Features

**Recording & transcription**

- One-tap record with a live waveform
- Background recording (keep talking while you switch apps)
- Import audio (`.m4a`, `.mp3`, `.wav`, and similar)
- On-device transcription, 90+ languages, optional translate-to-English
- Siri Shortcuts, Control Center widgets, Live Activities / Dynamic Island while recording or downloading models

**Writing & sharing**

- Blog posts, meeting notes, or personal notes
- Streaming generation (text appears as it writes)
- LinkedIn posts and Instagram captions with hashtags
- Search across your history
- Long recordings get chunked so they don’t choke the model

**Privacy & storage**

- No account, no analytics, no telemetry
- Recordings and posts stored locally
- Offline after the one-time model download
- Open source — you can read the code

## Try it

1. [Install Voice Blogger](https://apps.apple.com/us/app/voice-blogger/id6777303710)
2. Download the models once on Wi-Fi (a couple GB)
3. Record or drop in an audio file → generate → share

**Build from source:** open `iOS App/VoiceBlogger/VoiceBlogger.xcodeproj` in Xcode 16+ on a real iPhone (iOS 18+). See [CONTRIBUTING.md](CONTRIBUTING.md). Mac batch CLI is under `cliTools/`.

## Stack

SwiftUI, SwiftData, on-device speech-to-text + on-device LLM (Apple Neural Engine / MLX), App Intents.

## License

[Apache License 2.0](LICENSE) · [Privacy policy](PrivacyPolicy.md)

<div align="center">

Made for people who think better out loud.

[![Download on the App Store](https://img.shields.io/badge/Download_on_the-App_Store-0D96F6?style=for-the-badge&logo=apple&logoColor=white)](https://apps.apple.com/us/app/voice-blogger/id6777303710)

</div>
