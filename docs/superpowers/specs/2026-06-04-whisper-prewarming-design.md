# Whisper Pre-warming Design

**Date:** 2026-06-04  
**Status:** Approved

## Overview

Whisper (WhisperKit) currently loads from disk only during the first-ever download. On subsequent app launches the `whisperKit` property of `ModelDownloadManager` starts as `nil`, meaning the user waits for a full model load when they first try to transcribe. This feature pre-warms Whisper silently in the background so it is ready by the time the user taps Record or Upload.

A secondary concern is that `BlogView` keeps the LLM loaded after blog generation (so `InstagramView` can reuse it), but never releases it if the user navigates away without visiting Instagram — causing an OOM kill on the next transcription.

Both problems are fixed together because the solution to one enables the other: releasing the LLM on `BlogView` exit is the signal to re-warm Whisper.

---

## Architecture

### New method: `ModelDownloadManager.warmWhisper()`

```swift
func warmWhisper() async
```

- Guard conditions (all must be true to proceed):
  1. `isWhisperReady == true` — models are on disk
  2. `whisperKit == nil` — not already loaded
  3. No concurrent warm-up task running (`whisperWarmTask != nil`)
- Loads WhisperKit using the identical config as `downloadWhisper()` (same model ID, same compute options)
- Assigns the result to `self.whisperKit`
- Entirely silent — no progress updates, no UI state changes
- A private `Task?` property `whisperWarmTask` prevents concurrent loads and allows cancellation

### New private property: `ModelDownloadManager.whisperWarmTask`

```swift
@ObservationIgnored private var whisperWarmTask: Task<Void, Never>?
```

Checked in `warmWhisper()` to short-circuit if a warm-up is already in flight.

---

## Call Sites

### 1. App launch — `VoiceBloggerApp`

In the `WindowGroup` body, add a `.task` modifier on `ContentView`:

```swift
.task {
    if downloadManager.isWhisperReady {
        await downloadManager.warmWhisper()
    }
}
```

Fires once when the app window appears. If models are not yet downloaded the guard inside `warmWhisper()` exits immediately. This covers all subsequent launches after the initial download.

### 2. Post-transcription — `TranscriptionView.runTranscription()`

After `service.cleanup()` and `downloadManager.whisperKit = nil` (the existing cleanup block), add:

```swift
Task { await downloadManager.warmWhisper() }
```

This fires in the background while the user reads their transcript and decides whether to generate a blog post. Whisper will be ready again if they navigate back to record another clip.

### 3. Post-blog-generation — `BlogView.onDisappear`

Add `.onDisappear` to the `NavigationStack` in `BlogView`:

```swift
.onDisappear {
    guard !isGenerating else { return }
    downloadManager.releaseLLMService()
    Task { await downloadManager.warmWhisper() }
}
```

- `releaseLLMService()` is only called if `isGenerating == false` to avoid interrupting active generation
- `warmWhisper()` fires immediately after so Whisper is ready for the next session
- If the user navigated to `InstagramView` first, `InstagramView` already called `releaseLLMService()` on its own — calling it again is a no-op (the method is already guarded)

---

## Memory Safety

| Scenario | Behaviour |
|---|---|
| App launch, models ready | `warmWhisper()` loads WhisperKit (~300 MB) in background |
| User taps Record/Upload | `whisperKit` is already populated — `TranscriptionService.make(reusing:)` skips disk load |
| Transcription completes | `cleanup()` + `whisperKit = nil` frees memory; `warmWhisper()` begins reload |
| User generates blog | `prepareForLLMGeneration()` nils `whisperKit` again before LLM loads — `warmWhisper()` is not called here, so no race |
| User leaves BlogView | `releaseLLMService()` frees LLM; `warmWhisper()` reloads Whisper |
| User opens InstagramView before leaving BlogView | Instagram calls `releaseLLMService()` on success/error; BlogView's `onDisappear` calls it again safely (no-op) |
| `warmWhisper()` called twice concurrently | Second call is short-circuited by `whisperWarmTask != nil` guard |
| LLM is actively generating when `warmWhisper()` is called | Cannot happen — `warmWhisper()` is only triggered after `releaseLLMService()` or from the transcription cleanup path, neither of which overlaps with active LLM generation |

---

## Files Changed

| File | Change |
|---|---|
| `Services/ModelDownloadManager.swift` | Add `whisperWarmTask` property; add `warmWhisper()` method |
| `VoiceBloggerApp.swift` | Add `.task` modifier to trigger warm-up on launch |
| `Views/TranscriptionView.swift` | Fire `warmWhisper()` after transcription cleanup |
| `Views/BlogView.swift` | Add `.onDisappear` to release LLM and trigger `warmWhisper()` |

No new files. No new types. No UI changes.

---

## What Is Not In Scope

- Progress reporting for pre-warming (intentionally silent)
- Cancelling an in-flight warm-up when the user starts transcription (WhisperKit will load once; if `whisperKit` is already set when `TranscriptionService.make(reusing:)` is called, it is reused immediately regardless)
- Pre-warming the LLM (it is large enough that loading it speculatively would OOM the device)
