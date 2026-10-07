//
//  VoiceBloggerTests.swift
//  VoiceBloggerTests
//
//  Created by Kavin Shah on 5/30/26.
//

import AVFoundation
import Foundation
import Testing
import WhisperKit
@testable import VoiceBlogger

struct VoiceBloggerTests {

    @Test func blogGenerationHandoffTrimsTranscript() {
        let transcript = "\n\n  This is ready to become a blog post.  \n"

        #expect(BlogGenerationHandoff.preparedTranscript(from: transcript) == "This is ready to become a blog post.")
    }

    @Test func blogGenerationHandoffStripsUnreliableGenericSpeakerLabels() {
        let transcript = """
        [Speaker 1]: So, I think we should definitely do this deal for three million dollars.
        [Speaker 2]: okay let's meet in the middle let's do 2.5 million
        """

        #expect(BlogGenerationHandoff.preparedTranscript(from: transcript) == """
        So, I think we should definitely do this deal for three million dollars.
        okay let's meet in the middle let's do 2.5 million
        """)
    }

    @Test func blogGenerationHandoffRequiresTranscriptAndIdleState() {
        #expect(BlogGenerationHandoff.canGenerateBlog(from: "Transcript", isBusy: false))
        #expect(!BlogGenerationHandoff.canGenerateBlog(from: "   \n", isBusy: false))
        #expect(!BlogGenerationHandoff.canGenerateBlog(from: "Transcript", isBusy: true))
    }

    @Test func contentKindDefaultsToBlogPostWhenBetaDetectionIsOff() {
        let transcript = """
        Product sync meeting. Agenda was onboarding and pricing.
        We discussed launch blockers and decided to keep the beta invite-only.
        Action items: Maya follow up with legal by Friday.
        """

        #expect(BlogGenerationHandoff.contentKind(for: transcript) == .blogPost)
    }

    @Test func contentKindDetectsMeetingNotesWhenBetaDetectionIsOn() {
        let transcript = """
        Product sync meeting. Agenda was onboarding and pricing.
        We discussed launch blockers and decided to keep the beta invite-only.
        Action items: Maya follow up with legal by Friday. Jordan owns the pricing deck.
        Open question: whether support needs another walkthrough.
        """

        #expect(BlogGenerationHandoff.contentKind(for: transcript, automaticDetectionEnabled: true) == .meetingNotes)
    }

    @Test func contentKindDoesNotTrustHeuristicSpeakerCount() {
        let transcript = """
        So, I think we should definitely do this deal for three million dollars.
        okay let's meet in the middle let's do 2.5 million.
        """

        #expect(BlogGenerationHandoff.contentKind(
            for: transcript,
            speakerCount: 2,
            automaticDetectionEnabled: true
        ) == .blogPost)
    }

    @Test func contentKindDetectsRegularNotes() {
        let transcript = """
        Remember to buy coffee filters.
        - draft the outline for the workshop
        - look up the camera adapter
        - send Sam the invoice
        """

        #expect(BlogGenerationHandoff.contentKind(for: transcript, automaticDetectionEnabled: true) == .notes)
    }

    @Test func contentKindDetectsShortReminderAsNotes() {
        let transcript = "Remember to send Sam the invoice tomorrow."

        #expect(BlogGenerationHandoff.contentKind(for: transcript, automaticDetectionEnabled: true) == .notes)
    }

    @Test func contentKindDetectsAsteriskBulletsAsNotes() {
        let transcript = """
        * order coffee filters
        * draft workshop outline
        * send Sam the invoice
        """

        #expect(BlogGenerationHandoff.contentKind(for: transcript, automaticDetectionEnabled: true) == .notes)
    }

    @Test func contentKindDefaultsArticleLikeTranscriptToBlogPost() {
        let transcript = """
        I used to think consistency meant doing the exact same thing every day, but I learned that consistency is really about returning to the work after interruptions. That lesson changed how I plan creative projects and how I talk about progress with readers.
        """

        #expect(BlogGenerationHandoff.contentKind(for: transcript) == .blogPost)
    }

    @Test func promptBuilderDefaultBlogPromptAllowsCommonSenseFormatSelection() {
        let messages = PromptBuilder.contentMessages(
            transcript: "Remember to send Sam the invoice tomorrow.",
            contentKind: .blogPost
        )
        let system = messages.first?["content"] ?? ""
        let user = messages.dropFirst().first?["content"] ?? ""

        #expect(system.contains("use common sense and choose notes or meeting notes"))
        #expect(system.contains("preserve the transcript's natural intent"))
        #expect(system.contains("MARKDOWN OUTPUT CONTRACT"))
        #expect(system.contains("Return valid Markdown as the final answer"))
        #expect(system.contains("OUTPUT CONTRACT (mandatory)"))
        #expect(system.contains("NEVER output reasoning"))
        #expect(system.contains("FAITHFULNESS (no mistakes)"))
        #expect(!system.contains("REASONING (internal"))
        #expect(system.contains("Medium and long outputs should include multiple Markdown features"))
        #expect(system.contains("Make the post Markdown-rich"))
        #expect(system.contains("Always start with `# Title` on line 1"))
        #expect(system.contains("NEVER use the `>` character"))
        #expect(system.contains("TITLE CONTRACT (mandatory for Markdown documents)"))
        #expect(!system.contains("`>` blockquotes for notable spoken lines"))
        #expect(user.contains("Use common sense to decide whether it should read as a blog post, meeting notes, or personal notes"))
        #expect(user.contains("Reply with ONLY the finished document"))
    }

    @Test func promptBuilderRoutesMeetingNotesAwayFromBlogPrompt() {
        let messages = PromptBuilder.contentMessages(
            transcript: "Meeting agenda, decisions, and action items.",
            contentKind: .meetingNotes
        )
        let system = messages.first?["content"] ?? ""

        #expect(system.contains("meeting notes, not blog posts"))
        #expect(system.contains("Action Items"))
    }

    @Test func promptBuilderKeepsPersonalDictionaryPrivate() {
        let messages = PromptBuilder.contentMessages(
            transcript: "I met with Kavitha about the roadmap.",
            contentKind: .blogPost,
            vocabularyTerms: ["Kavitha", "VoiceBlogger"]
        )
        let system = messages.first?["content"] ?? ""
        let user = messages.dropFirst().first?["content"] ?? ""

        #expect(system.contains("PERSONAL DICTIONARY (PRIVATE)"))
        #expect(system.contains("NEVER mention, quote, list, summarize"))
        #expect(user.contains("Private spelling reference"))
        #expect(user.contains("Kavitha, VoiceBlogger"))
        #expect(user.contains("Transcript:"))
        #expect(!user.hasPrefix("Custom vocabulary"))
    }

    @Test func linkedinPromptIncludesTemplatesAndSinglePostContract() {
        let messages = PromptBuilder.linkedinMessages(blogContent: "We shipped the beta after reducing launch time by 35%.")
        let system = messages.first?["content"] ?? ""
        let user = messages.dropFirst().first?["content"] ?? ""

        #expect(system.contains("Write ONE LinkedIn post"))
        #expect(system.contains("101-150 words total"))
        #expect(system.contains("Do not invent facts, metrics, or claims"))
        #expect(system.contains("Hashtags: 3-5 on the final line only"))
        #expect(user.contains("Write a LinkedIn post from this content"))
        #expect(user.contains("We shipped the beta"))
    }

    @Test func markdownProcessorParsesCommonBlogBlocks() {
        let markdown = """
        # Title

        Intro with **bold** text.

        ## Section

        - First
          - Nested
        - Second

        3. Third
        4. Fourth

        > Quote line
        >
        > - quoted list

        | Name | Score |
        | :--- | ---: |
        | One | 10 |

        ```swift
        let value = 1
        ```

        ---
        """

        let blocks = MarkdownProcessor.parse(markdown)

        #expect(blocks.count == 9)
        #expect(blocks[0] == .heading(level: 1, text: "Title"))
        #expect(blocks[1] == .paragraph("Intro with **bold** text."))
        #expect(blocks[2] == .heading(level: 2, text: "Section"))

        guard case .unorderedList(let unorderedItems) = blocks[3] else {
            Issue.record("Expected unordered list")
            return
        }
        #expect(unorderedItems.map(\.text) == ["First", "Second"])
        #expect(unorderedItems[0].children == [.unorderedList([.init(marker: "-", text: "Nested", children: [])])])

        guard case .orderedList(let start, let orderedItems) = blocks[4] else {
            Issue.record("Expected ordered list")
            return
        }
        #expect(start == 3)
        #expect(orderedItems.map(\.marker) == ["3.", "4."])
        #expect(orderedItems.map(\.text) == ["Third", "Fourth"])

        guard case .blockquote(let quoteBlocks) = blocks[5] else {
            Issue.record("Expected blockquote")
            return
        }
        #expect(quoteBlocks == [.paragraph("Quote line"), .unorderedList([.init(marker: "-", text: "quoted list", children: [])])])

        guard case .table(let table) = blocks[6] else {
            Issue.record("Expected table")
            return
        }
        #expect(table.columns.map(\.title) == ["Name", "Score"])
        #expect(table.columns.map(\.alignment) == [.leading, .trailing])
        #expect(table.rows == [["One", "10"]])

        #expect(blocks[7] == .codeBlock(language: "swift", code: "let value = 1"))
        #expect(blocks[8] == .divider)
    }

    @Test func generationOutputGuardStopsObviousRunawayText() {
        let repeated = Array(repeating: "This paragraph is repeating without adding anything new.", count: 4)
            .joined(separator: "\n")

        #expect(GenerationOutputGuard.hasRunawayRepetition(in: repeated))
    }

    @Test func generationOutputGuardAllowsNormalRepeatedPhrasing() {
        let post = """
        # Weekly Notes

        The product launch came up several times because it mattered to every part of the plan.
        The team discussed launch readiness, customer support, and follow-up tasks.
        The product launch also shaped the marketing timeline, but each section added new detail.
        """

        #expect(!GenerationOutputGuard.hasRunawayRepetition(in: post))
    }

    @Test func generationOutputSanitizerStripsThinkBlocksAndPreamble() {
        let raw = """
        <think>
        First I will identify the format and list the facts.
        </think>
        Here is the blog post:

        # Weekly Notes

        - Send Sam the invoice
        """

        let cleaned = GenerationOutputSanitizer.sanitize(raw)
        #expect(!cleaned.contains("<think>"))
        #expect(!cleaned.contains("First I will identify"))
        #expect(!cleaned.contains("Here is the blog post"))
        #expect(cleaned.hasPrefix("# Weekly Notes"))
        #expect(cleaned.contains("Send Sam the invoice"))
    }

    @Test func generationOutputSanitizerStripsLabeledReasoning() {
        let raw = """
        REASONING:
        This looks like personal notes about errands.

        - Order coffee filters
        - Draft workshop outline
        """

        let cleaned = GenerationOutputSanitizer.sanitize(raw)
        #expect(!cleaned.contains("REASONING"))
        #expect(!cleaned.contains("This looks like personal notes"))
        #expect(cleaned.contains("Order coffee filters"))
    }

    @Test func generationOutputSanitizerHidesOpenThinkDuringStreaming() {
        let partial = """
        <think>
        Still figuring out the structure
        """

        #expect(GenerationOutputSanitizer.sanitizeForDisplay(partial).isEmpty)

        let closedThenContent = """
        <think>plan</think>
        - Buy milk
        """
        #expect(GenerationOutputSanitizer.sanitizeForDisplay(closedThenContent) == "- Buy milk")
    }

    @Test func generationCompletionValidateSanitizesBeforeAccepting() throws {
        let raw = """
        Sure, here are the notes:

        - Call Jordan
        """
        let cleaned = try LLMGenerationCompletion.validate(raw)
        #expect(cleaned == "- Call Jordan")
    }

    @Test func markdownProcessorParsesSetextAndIndentedCode() {
        let markdown = """
        Setext Title
        ============

            indented code
            continues
        """

        let blocks = MarkdownProcessor.parse(markdown)

        #expect(blocks == [
            .heading(level: 1, text: "Setext Title"),
            .codeBlock(language: nil, code: "indented code\ncontinues")
        ])
    }

    @Test func transcriptionFilterRemovesWhisperControlTokens() {
        let text = "<|startoftranscript|><|en|><|0.00|> Hello world <|endoftext|>"

        #expect(TranscriptionService.filterTokens(text) == "Hello world")
    }

    @Test func transcriptionFilterCanDetectPlaceholderOnlyOutput() {
        let text = "<|startoftranscript|>[Speaking in a foreign language]<|endoftext|>"

        #expect(TranscriptionService.filterTokens(text).isEmpty)
    }

    @Test func transcriptionFilterRemovesNonSpeechAnnotations() {
        let text = "<|startoftranscript|><|en|><|0.00|> [Noise] Today I want to talk about launch notes. [Laughter] <|endoftext|>"

        #expect(TranscriptionService.filterTokens(text) == "Today I want to talk about launch notes.")
    }

    @Test func transcriptMergeDedupesOverlappingWords() {
        let existing = "The quick brown fox jumps"
        let newChunk = "fox jumps over the lazy dog"
        #expect(TranscriptMergeUtility.merge(existing: existing, newChunk: newChunk) == "The quick brown fox jumps over the lazy dog")
    }

    @Test func transcriptMergeHandlesEmptyExisting() {
        #expect(TranscriptMergeUtility.merge(existing: "", newChunk: "Hello world") == "Hello world")
    }

    @Test func transcriptMergeSkipsDuplicateChunk() {
        let existing = "one two three"
        #expect(TranscriptMergeUtility.merge(existing: existing, newChunk: "two three") == "one two three")
    }

    @Test func modelIntegrityRejectsUntrustedPartialDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let key = "model-integrity-\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(at: directory)
            ModelIntegrityChecker.invalidate(forKey: key)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: directory.appendingPathComponent("config.json"))

        #expect(!ModelIntegrityChecker.verify(directory: directory, storedKey: key))
    }

    @Test func modelIntegrityAcceptsOnlyStoredMatchingFingerprint() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let key = "model-integrity-\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(at: directory)
            ModelIntegrityChecker.invalidate(forKey: key)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("complete".utf8).write(to: directory.appendingPathComponent("weights.safetensors"))
        let fingerprint = try #require(ModelIntegrityChecker.fingerprint(of: directory))
        ModelIntegrityChecker.store(fingerprint: fingerprint, forKey: key)

        #expect(ModelIntegrityChecker.verify(directory: directory, storedKey: key))

        try Data("changed".utf8).write(to: directory.appendingPathComponent("weights.safetensors"))
        #expect(!ModelIntegrityChecker.verify(directory: directory, storedKey: key))
    }

    @Test func markdownProcessorParsesGFMTaskLists() {
        let blocks = MarkdownProcessor.parse("""
        - [x] Download models
        - [ ] Generate the post
        """)

        #expect(blocks == [
            .unorderedList([
                .init(marker: "☑︎", text: "Download models", children: []),
                .init(marker: "☐", text: "Generate the post", children: [])
            ])
        ])
    }

    @Test func transcriptionRefinementFallbackDoesNotShowFailure() {
        let resolution = TranscriptionFailurePolicy.resolve(
            isRefinement: true,
            hasUsableTranscript: true
        )

        #expect(resolution == .retainPreview)
        #expect(!resolution.showsError)
        #expect(resolution.transcriptionState == .complete)
    }

    @Test func transcriptionFailureWithoutTranscriptRemainsRetryable() {
        let resolution = TranscriptionFailurePolicy.resolve(
            isRefinement: false,
            hasUsableTranscript: false
        )

        #expect(resolution == .retryableFailure)
        #expect(resolution.showsError)
        #expect(resolution.transcriptionState == .inProgress)
    }

    @Test func generationCompletionRejectsWhitespaceOnlyOutput() {
        #expect(throws: LLMGenerationError.emptyOutput) {
            try LLMGenerationCompletion.validate(" \n\t ")
        }
    }

    @Test func hubDownloadPolicyUsesBoundedParallelism() {
        #expect(HubDownloadPolicy.maximumConcurrentTransfers >= 4)
        #expect(HubDownloadPolicy.maximumConcurrentTransfers <= 8)
    }

    @Test func cancellationDoesNotInvalidateDownloadedModels() {
        #expect(!ModelLoadFailurePolicy.shouldInvalidate(CancellationError(), integrityMatches: false))
        #expect(!ModelLoadFailurePolicy.shouldInvalidate(
            URLError(.cannotDecodeContentData),
            integrityMatches: true
        ))
        #expect(ModelLoadFailurePolicy.shouldInvalidate(
            URLError(.cannotDecodeContentData),
            integrityMatches: false
        ))
    }

    @Test func markdownProcessorPreservesHardLineBreaks() {
        let blocks = MarkdownProcessor.parse("First line  \nSecond line")
        #expect(blocks == [.paragraph("First line  \nSecond line")])
    }

    @Test func markdownProcessorResolvesReferenceLinksAcrossDocument() {
        let blocks = MarkdownProcessor.parse("""
        Read [the guide][guide].

        [guide]: https://example.com
        """)

        #expect(blocks == [.paragraph("Read [the guide](https://example.com).")])
    }

    @Test func markdownProcessorLeavesReferencesInsideCodeFencesUntouched() {
        let blocks = MarkdownProcessor.parse("""
        ```
        [guide]: https://inside.example
        [guide]
        ```

        [guide]: https://outside.example
        """)

        #expect(blocks == [
            .codeBlock(
                language: nil,
                code: "[guide]: https://inside.example\n[guide]"
            )
        ])
    }

    @Test func markdownProcessorResolvesShortcutReferencesWithTitles() {
        let blocks = MarkdownProcessor.parse("""
        Read [Guide].

        [guide]: https://example.com "Documentation"
        """)

        #expect(blocks == [
            .paragraph(#"Read [Guide](https://example.com "Documentation")."#)
        ])
    }

    @Test func markdownProcessorLeavesReferencesInsideInlineAndIndentedCodeUntouched() {
        let blocks = MarkdownProcessor.parse("""
        Use `[guide]` in docs.

            [guide]

        [guide]: https://example.com
        """)

        #expect(blocks == [
            .paragraph("Use `[guide]` in docs."),
            .codeBlock(language: nil, code: "[guide]")
        ])
    }

    @Test func installedModelsAreKeptAcrossUpdatesWithoutReinstall() {
        #expect(
            ModelInstallRetentionPolicy.shouldKeepInstalledModel(
                directoryExists: true,
                integrityMatches: false,
                wasMarkedReady: true
            )
        )
        #expect(
            ModelInstallRetentionPolicy.shouldKeepInstalledModel(
                directoryExists: true,
                integrityMatches: true,
                wasMarkedReady: false
            )
        )
        #expect(
            !ModelInstallRetentionPolicy.shouldKeepInstalledModel(
                directoryExists: true,
                integrityMatches: false,
                wasMarkedReady: false
            )
        )
        #expect(
            !ModelInstallRetentionPolicy.shouldKeepInstalledModel(
                directoryExists: false,
                integrityMatches: false,
                wasMarkedReady: true
            )
        )
    }

    @Test func localModelDirectoryIsPreferredOverNetworkReinstall() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let key = "llm-integrity-\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(at: directory)
            ModelIntegrityChecker.invalidate(forKey: key)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: directory.appendingPathComponent("config.json"))

        #expect(!ModelIntegrityChecker.verify(directory: directory, storedKey: key))
        #expect(!LocalModelTrustPolicy.shouldPreferNetworkResume(hasLocalDirectory: true))
        #expect(LocalModelTrustPolicy.shouldPreferNetworkResume(hasLocalDirectory: false))
    }

    @Test func cancelledWhisperValidationDoesNotContinueDownload() {
        #expect(
            WhisperDownloadContinuation.shouldContinueAfterLocalValidation(
                validationSucceeded: false,
                runStillActive: false,
                isCancelled: true
            ) == false
        )
        #expect(
            WhisperDownloadContinuation.shouldContinueAfterLocalValidation(
                validationSucceeded: false,
                runStillActive: true,
                isCancelled: false
            )
        )
    }

    @Test func inferencePerformancePolicySkipsRefinementForShortLiveRecordings() {
        #expect(InferencePerformancePolicy.shouldSkipFullFileRefinement(
            recordingDuration: 8,
            previewText: "This is a complete short recording preview.",
            hadLivePreview: true
        ))
    }

    @Test func inferencePerformancePolicyKeepsRefinementForLongRecordings() {
        #expect(!InferencePerformancePolicy.shouldSkipFullFileRefinement(
            recordingDuration: 120,
            previewText: "A longer meeting preview that still needs a full-file pass for accuracy.",
            hadLivePreview: true
        ))
    }

    @Test func inferencePerformancePolicyNeverSkipsWithoutLivePreview() {
        #expect(!InferencePerformancePolicy.shouldSkipFullFileRefinement(
            recordingDuration: 5,
            previewText: "Imported audio without live preview.",
            hadLivePreview: false
        ))
    }

    @Test func inferencePerformancePolicyUsesVADForLongAudio() {
        #expect(InferencePerformancePolicy.whisperChunkingStrategy(audioDuration: 60) == .vad)
        #expect(InferencePerformancePolicy.whisperChunkingStrategy(audioDuration: 20) == .none)
    }

    @Test func inferencePerformancePolicyParallelChunkWidthScalesWithRAM() {
        #expect(InferencePerformancePolicy.parallelChunkSummaryWidth >= 1)
        #expect(InferencePerformancePolicy.parallelChunkSummaryWidth <= 3)
    }

    @Test func speechGainControllerBoostsQuietPeaks() {
        let controller = SpeechGainController()
        let quietGain = controller.gain(forPeak: 0.02)
        let loudGain = controller.gain(forPeak: 0.7)

        #expect(quietGain > loudGain)
        #expect(quietGain > 2.0)
        #expect(loudGain <= 1.1)
    }

    @Test func recordingArchiveKeepsFullBandwidth() {
        #expect(RecordingAudioSettings.archiveSampleRate == 48_000)
        #expect(RecordingAudioSettings.whisperSampleRate == 16_000)
        #expect(RecordingAudioSettings.archiveSampleRate(matching: 48_000) == 48_000)
        #expect(RecordingAudioSettings.archiveSampleRate(matching: 44_100) == 44_100)
        #expect(RecordingAudioSettings.archiveSampleRate(matching: 16_000) == 48_000)
        #expect(RecordingAudioSettings.archiveBitRate >= 128_000)

        let settings = RecordingAudioSettings.archiveFileSettings()
        #expect(settings[AVSampleRateKey] as? Double == 48_000)
        #expect(settings[AVEncoderBitRateKey] as? Int == RecordingAudioSettings.archiveBitRate)
        #expect(settings[AVNumberOfChannelsKey] as? Int == 1)
        #expect(settings[AVFormatIDKey] as? AudioFormatID == kAudioFormatMPEG4AAC)

        let lossless = RecordingAudioSettings.losslessArchiveSettings()
        #expect(lossless[AVSampleRateKey] as? Double == 48_000)
        #expect(lossless[AVLinearPCMBitDepthKey] as? Int == 16)
        #expect(lossless[AVFormatIDKey] as? AudioFormatID == kAudioFormatLinearPCM)
    }

    @Test func recordingConverterReservesResamplerTail() {
        let inputFrames = 4096
        let truncated = Int(Double(inputFrames) * 16_000 / 48_000)
        let capacity = RecordingAudioSettings.outputFrameCapacity(
            inputFrames: inputFrames,
            sourceSampleRate: 48_000,
            targetSampleRate: 16_000
        )

        #expect(truncated == 1_365)
        #expect(capacity >= truncated + 256)
    }

    @Test func speechGainControllerAppliesBoundedBoost() {
        var samples: [Float] = [0.01, -0.008, 0.012, -0.009]
        SpeechGainController.applyGain(5.0, to: &samples)

        let peak = samples.map { abs($0) }.max() ?? 0
        #expect(peak > 0.04)
        #expect(peak <= 1.0)
    }

    @Test func highQualityIsRejectedOnPhonesBelowEightGigabytes() {
        let threeGB: UInt64 = 2_961_514_496
        let fourGB: UInt64 = 3_840_000_000
        let sixGBMarketed: UInt64 = 5_912_567_808
        let sixGiB = UInt64(6) * 1024 * 1024 * 1024
        let eightGB: UInt64 = 8_027_963_392

        #expect(DeviceRAMTier.tier(forPhysicalRAMBytes: threeGB) == .constrained)
        #expect(DeviceRAMTier.tier(forPhysicalRAMBytes: fourGB) == .standard)
        #expect(DeviceRAMTier.tier(forPhysicalRAMBytes: sixGBMarketed) == .standard)
        #expect(DeviceRAMTier.tier(forPhysicalRAMBytes: sixGiB) == .standard)
        #expect(DeviceRAMTier.tier(forPhysicalRAMBytes: eightGB) == .ample)

        #expect(!ModelQualityLevel.high.isSupported(on: .standard))
        #expect(!ModelQualityLevel.high.isSupported(on: .constrained))
        #expect(ModelQualityLevel.high.isSupported(on: .ample))
        #expect(!ModelQualityLevel.medium.isSupported(on: .constrained))
        #expect(ModelQualityLevel.low.isSupported(on: .constrained))

        #expect(ModelQualityLevel.clamped(.high, to: .standard) == .medium)
        #expect(ModelQualityLevel.clamped(.high, to: .constrained) == .low)
        #expect(ModelQualityLevel.clamped(.medium, to: .constrained) == .low)
        #expect(ModelQualityLevel.recommended(for: .standard) == .medium)
        #expect(ModelQualityLevel.recommended(for: .constrained) == .low)
        #expect(ModelQualityLevel.recommended(for: .ample) == .high)
    }

    @Test func storedHighQualityIsClampedBeforeItCanLoad() {
        let clamped = ModelQualityResolution.decide(
            ModelQualityResolution.Input(
                tier: .standard,
                storedRaw: ModelQualityLevel.high.rawValue,
                isLocked: true,
                whisperReady: true
            )
        )
        #expect(clamped.level == .medium)
        #expect(clamped.shouldPersist)

        let kept = ModelQualityResolution.decide(
            ModelQualityResolution.Input(
                tier: .ample,
                storedRaw: ModelQualityLevel.high.rawValue,
                isLocked: false,
                whisperReady: true
            )
        )
        #expect(kept.level == .high)
        #expect(kept.shouldPersist)
    }

    @Test func legacyInstallFallsBackWhenBalancedDoesNotFit() {
        let standard = ModelQualityResolution.decide(
            ModelQualityResolution.Input(tier: .standard, storedRaw: nil, isLocked: false, whisperReady: true)
        )
        #expect(standard.level == .medium)
        #expect(standard.shouldPersist)

        let constrained = ModelQualityResolution.decide(
            ModelQualityResolution.Input(tier: .constrained, storedRaw: nil, isLocked: false, whisperReady: true)
        )
        #expect(constrained.level == .low)
    }

    @Test func oversizedInstalledModelsAreNotSafeToLoad() {
        #expect(!ModelQualityLevel.isSafeToLoad(
            whisperModelID: ModelQualityLevel.high.whisperModelID,
            on: .standard
        ))
        #expect(!ModelQualityLevel.isSafeToLoad(
            whisperModelID: "openai_whisper-large-v3",
            on: .constrained
        ))
        #expect(!ModelQualityLevel.isSafeToLoad(
            llmModelID: ModelQualityLevel.high.llmModelID,
            on: .standard
        ))
        #expect(ModelQualityLevel.isSafeToLoad(
            llmModelID: ModelQualityLevel.low.llmModelID,
            on: .constrained
        ))
        #expect(ModelQualityLevel.isSafeToLoad(
            whisperModelID: ModelQualityLevel.low.whisperModelID,
            on: .constrained
        ))
    }

    @Test func memoryBudgetStaysAtTheModelFootprint() {
        let high = ModelMemoryBudget.llmLoadMegabytes(for: .high)
        #expect(high >= 2000)
        let oneByteShort = (UInt64(high) * 1024 * 1024) - 1
        #expect(!ModelMemoryBudget.allowsLoad(availableBytes: oneByteShort, requiredMB: high))
        #expect(ModelMemoryBudget.allowsLoad(availableBytes: UInt64(high) * 1024 * 1024, requiredMB: high))
        #expect(ModelMemoryBudget.llmLoadMegabytes(for: .low) < high)
        #expect(ModelMemoryBudget.whisperCompileMegabytes(for: .high) > ModelMemoryBudget.whisperCompileMegabytes(for: .low))
        #expect(ModelMemoryBudget.allowsLoad(availableBytes: 0, requiredMB: high))
    }

    @Test func highQualityGenerationStaysInsideOneForwardPass() {
        #expect(InferencePerformancePolicy.parallelChunkSummaryWidth(quality: .high, tier: .ample) == 1)
        #expect(InferencePerformancePolicy.parallelChunkSummaryWidth(quality: .medium, tier: .ample) == 3)
        #expect(InferencePerformancePolicy.parallelChunkSummaryWidth(quality: .low, tier: .constrained) == 1)

        let highProfile = InferencePerformancePolicy.llmMemoryProfile(quality: .high, tier: .ample)
        #expect(highProfile.quantizeKV)
        #expect(highProfile.prefillStepSize == 512)
        #expect(ModelQualityLevel.high.mlxCacheLimitBytes(on: .ample) == 512 * 1024 * 1024)

        let balancedProfile = InferencePerformancePolicy.llmMemoryProfile(quality: .medium, tier: .ample)
        #expect(!balancedProfile.quantizeKV)
        #expect(balancedProfile.prefillStepSize == 1024)
    }

    @Test func memoryPressureDoesNotInvalidateAGoodModel() {
        #expect(!ModelLoadFailurePolicy.shouldInvalidate(
            LLMLoadError.insufficientMemory,
            integrityMatches: false
        ))
    }

    @Test func mlxStartupKeepsARealGPUArchitecture() {
        #expect(MLXMetalStartup.resolvedArchitecture(reported: "applegpu_g16p", runningOnMac: false) == "applegpu_g16p")
        #expect(MLXMetalStartup.resolvedArchitecture(reported: "applegpu_g14g", runningOnMac: true) == "applegpu_g14g")
    }

    @Test func mlxStartupReplacesAMissingGPUName() {
        #expect(MLXMetalStartup.resolvedArchitecture(reported: nil, runningOnMac: false) == "applegpu_g15p")
        #expect(MLXMetalStartup.resolvedArchitecture(reported: "", runningOnMac: false) == "applegpu_g15p")
        #expect(MLXMetalStartup.resolvedArchitecture(reported: nil, runningOnMac: true) == "applegpu_g14g")
        MLXMetalStartup.installIfNeeded()
        let arch = getenv("MLX_METAL_GPU_ARCH").map { String(cString: $0) } ?? ""
        #expect(!arch.isEmpty)
    }

    @Test func lockedRecordingUsesProtectionThatAllowsBackgroundWrites() {
        #expect(RecordingStorage.protection == .completeUntilFirstUserAuthentication)
    }

    @Test func deletingHistoryRemovesTheAudioFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("voiceblogger-delete-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let filename = "take.caf"
        let file = directory.appendingPathComponent(filename)
        try Data("audio".utf8).write(to: file)
        let outside = directory.deletingLastPathComponent()
            .appendingPathComponent("vb-secret-\(UUID().uuidString).txt")
        try Data("secret".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }

        RecordingStorage.deleteAudioFile(named: filename, in: directory)
        RecordingStorage.deleteAudioFile(named: "../\(outside.lastPathComponent)", in: directory)

        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test func resetRemovesSpeechAndWritingModelCaches() {
        let documents = URL(fileURLWithPath: "/tmp/docs", isDirectory: true)
        let caches = URL(fileURLWithPath: "/tmp/caches", isDirectory: true)
        let urls = ModelCacheLocations.huggingFaceDirectories(documents: documents, caches: caches)
        #expect(urls.contains(documents.appendingPathComponent("huggingface", isDirectory: true)))
        #expect(urls.contains(caches.appendingPathComponent("huggingface", isDirectory: true)))
    }

    @Test func sameTurnStartAndStopKeepsStopAfterStart() {
        #expect(RecordingIntentSequence.steps(startPending: true, stopPending: true) == [.start, .stop])
        #expect(RecordingIntentSequence.steps(startPending: false, stopPending: true) == [.stop])
        #expect(RecordingIntentSequence.steps(startPending: true, stopPending: false) == [.start])
    }

    @Test func emptyTranscriptionCallbacksStillCountAsProgress() {
        #expect(TranscriptionStallPolicy.resetsTimer(callbackInvoked: true))
        #expect(!TranscriptionStallPolicy.resetsTimer(callbackInvoked: false))
    }

    @Test func polishRejectsATruncatedLongTranscript() {
        let original = String(repeating: "We shipped the beta after the review. ", count: 80)
        let truncated = String(original.prefix(400))
        #expect(TranscriptPolishPolicy.looksTruncated(original: original, polished: truncated, maxTokens: 800))
        #expect(
            TranscriptPolishPolicy.acceptedText(original: original, polished: truncated, maxTokens: 800) == original
        )
    }

    @Test func polishKeepsALightlyCleanedTranscript() {
        let original = "Um, we shipped the beta after the review, you know."
        let polished = "We shipped the beta after the review."
        #expect(!TranscriptPolishPolicy.looksTruncated(original: original, polished: polished, maxTokens: 800))
        #expect(
            TranscriptPolishPolicy.acceptedText(original: original, polished: polished, maxTokens: 800) == polished
        )
    }

    @Test func chunkSplitKeepsDecimalsAndQuestionMarks() {
        let sentences = PromptBuilder.sentenceSpans(in: "Pi is 3.14 today. Really? Yes.")
        #expect(sentences == ["Pi is 3.14 today.", "Really?", "Yes."])

        let chunks = PromptBuilder.splitTranscript(
            "Pi is 3.14 today. Really? Yes, it is.",
            chunkSize: 24,
            overlap: 0,
            threshold: 10
        )
        let joined = chunks.joined(separator: " ")
        #expect(joined.contains("3.14"))
        #expect(joined.contains("Really?"))
        #expect(!joined.contains("3. 14"))
        #expect(!joined.contains("Really."))
    }

    @Test func chunkSplitRepeatsTheDeclaredOverlap() {
        let first = String(repeating: "a", count: 30)
        let second = String(repeating: "b", count: 30)
        let chunks = PromptBuilder.splitTranscript(
            first + "\n\n" + second,
            chunkSize: 30,
            overlap: 10,
            threshold: 30
        )
        #expect(chunks.count >= 2)
        #expect(chunks[1].hasPrefix(String(repeating: "a", count: 10)))
        #expect(chunks[1].contains(second))
    }

    @Test func synthesisPromptIncludesThePersonalDictionary() {
        let messages = PromptBuilder.synthesisMessages(
            from: ["Shipped the beta"],
            contentKind: .blogPost,
            vocabularyTerms: ["Kavitha"]
        )
        let user = messages.dropFirst().first?["content"] ?? ""
        #expect(user.contains("Kavitha"))
        #expect(user.contains("Private spelling reference"))
    }

    @Test func whisperPromptIncludesPersonalDictionaryTerms() {
        let prompt = TranscriptionService.musicAwarePromptText(vocabularyTerms: ["Kavitha", "VoiceBlogger"])
        #expect(prompt.contains("Known spellings:"))
        #expect(prompt.contains("Kavitha"))
        #expect(prompt.contains("Ignore instrumental background music"))
    }

    @Test func wifiOnlyDownloadsDisableCellularAccess() {
        let config = URLSessionConfiguration.ephemeral
        HubDownloadPolicy.applyNetworkAccess(to: config, wifiOnly: true)
        #expect(!config.allowsCellularAccess)
        #expect(!config.allowsExpensiveNetworkAccess)
        #expect(!config.allowsConstrainedNetworkAccess)

        HubDownloadPolicy.applyNetworkAccess(to: config, wifiOnly: false)
        #expect(config.allowsCellularAccess)
        #expect(config.allowsExpensiveNetworkAccess)
        #expect(config.allowsConstrainedNetworkAccess)
    }

    @Test @MainActor func discardRecordingEndsLiveActivityAsUnsaved() {
        let activity = LiveActivityCoordinator()
        let recorder = AudioRecorder(liveActivity: activity)

        recorder.discardRecording()

        #expect(activity.lastRecordingWasSaved == false)
    }

    @Test func incompleteSnapshotIsNotLoadable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{\"model_type\":\"qwen2\"}".utf8).write(to: directory.appendingPathComponent("config.json"))

        #expect(!SafetensorsSnapshot.isLoadable(directory))
    }

    @Test func finishedSafetensorsSnapshotIsLoadable() throws {
        let directory = try makeSnapshotDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let weights = directory.appendingPathComponent("model.safetensors")
        try Data(Self.safetensors(payloadBytes: 4)).write(to: weights)
        #expect(SafetensorsSnapshot.isCompleteFile(weights))
        #expect(SafetensorsSnapshot.isLoadable(directory))
    }

    @Test func truncatedSafetensorsSnapshotIsNotLoadable() throws {
        let directory = try makeSnapshotDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var truncated = Data(Self.safetensors(payloadBytes: 64))
        truncated.removeLast(32)
        try truncated.write(to: directory.appendingPathComponent("model.safetensors"))

        #expect(!SafetensorsSnapshot.isLoadable(directory))
    }

    @Test func snapshotIndexRejectsAFileSmallerThanTheTensorPayload() throws {
        let directory = try makeSnapshotDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(Self.safetensors(payloadBytes: 4)).write(to: directory.appendingPathComponent("model.safetensors"))
        let index = """
        {"metadata":{"total_size":791429257},"weight_map":{"model.layers.0.input_layernorm.weight":"model.safetensors"}}
        """
        try Data(index.utf8).write(to: directory.appendingPathComponent("model.safetensors.index.json"))

        #expect(!SafetensorsSnapshot.isLoadable(directory))
    }

    @Test func symlinkedSafetensorsBlobIsLoadable() throws {
        let directory = try makeSnapshotDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let blob = directory.appendingPathComponent("blob")
        try Data(Self.safetensors(payloadBytes: 4)).write(to: blob)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("model.safetensors"),
            withDestinationURL: blob
        )

        #expect(SafetensorsSnapshot.isLoadable(directory))
    }

    @Test func droppedConnectionIsRetried() {
        let lost = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
        #expect(LLMNetworkRetry.shouldRetry(lost, attempt: 0))
        #expect(LLMNetworkRetry.shouldRetry(lost, attempt: 2))
        #expect(!LLMNetworkRetry.shouldRetry(lost, attempt: 3))
        #expect(LLMNetworkRetry.delaySeconds(afterFailure: 1) == 2)
        #expect(LLMNetworkRetry.delaySeconds(afterFailure: 3) == 8)
    }

    @Test func cancellationAndMissingWeightsAreNotRetried() {
        #expect(!LLMNetworkRetry.shouldRetry(CancellationError(), attempt: 0))
        #expect(!LLMNetworkRetry.shouldRetry(LLMLoadError.insufficientMemory, attempt: 0))
        #expect(!LLMNetworkRetry.shouldRetry(DownloadBlockedOnCellularError(), attempt: 0))
        #expect(!LLMNetworkRetry.shouldRetry(ModelValidationError.missingModelArtifacts, attempt: 0))
        #expect(LLMNetworkRetry.isIncompleteWeightError(
            NSError(domain: "MLX", code: 1, userInfo: [NSLocalizedDescriptionKey: "keyNotFound(path: [\"model\", \"layers\", \"0\", \"input_layernorm\", \"weight\"])"])
        ))
    }

    private func makeSnapshotDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{\"model_type\":\"qwen2\"}".utf8).write(to: directory.appendingPathComponent("config.json"))
        return directory
    }

    private static func safetensors(payloadBytes: Int) -> Data {
        let header = #"{"w":{"dtype":"U8","shape":[\#(payloadBytes)],"data_offsets":[0,\#(payloadBytes)]}}"#
        let headerData = Data(header.utf8)
        var file = Data()
        let length = UInt64(headerData.count).littleEndian
        withUnsafeBytes(of: length) { file.append(contentsOf: $0) }
        file.append(headerData)
        file.append(Data(repeating: 1, count: payloadBytes))
        return file
    }

    @Test @MainActor func leavingBlogForSocialKeepsTheWritingModelResident() {
        let post = BlogPost(transcript: "Hello")
        #expect(AppStage.viewingInstagram(post: post).keepsWritingAssistantLoaded)
        #expect(AppStage.viewingLinkedIn(post: post).keepsWritingAssistantLoaded)
        #expect(!AppStage.recording.keepsWritingAssistantLoaded)
        #expect(!AppStage.transcribing(post: post).keepsWritingAssistantLoaded)
    }

    @Test func blogOverflowMenuKeepsATappableLabel() {
        #expect(BlogOverflowMenu.accessibilityLabel == "More options")
        #expect(BlogOverflowMenu.systemImage == "ellipsis.circle")
    }

    @Test func blogOverflowMenuShowsContentActionsWhenIdleWithText() {
        #expect(BlogOverflowMenu.includesContentActions(displayText: "# Hello", isGenerating: false))
        #expect(!BlogOverflowMenu.includesContentActions(displayText: "# Hello", isGenerating: true))
        #expect(!BlogOverflowMenu.includesContentActions(displayText: "", isGenerating: false))
        #expect(!BlogOverflowMenu.includesContentActions(displayText: "", isGenerating: true))
    }

}
