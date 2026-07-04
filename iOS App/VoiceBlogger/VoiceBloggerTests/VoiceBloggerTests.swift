//
//  VoiceBloggerTests.swift
//  VoiceBloggerTests
//
//  Created by Kavin Shah on 5/30/26.
//

import Testing
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
        #expect(system.contains("Medium and long outputs should include multiple Markdown features"))
        #expect(system.contains("Make the post Markdown-rich"))
        #expect(user.contains("Use common sense to decide whether it should read as a blog post, meeting notes, or personal notes"))
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

    @Test func linkedinPromptIncludesTemplatesAndSinglePostContract() {
        let messages = PromptBuilder.linkedinMessages(blogContent: "We shipped the beta after reducing launch time by 35%.")
        let system = messages.first?["content"] ?? ""
        let user = messages.dropFirst().first?["content"] ?? ""

        #expect(system.contains("Original Research / Data Insights"))
        #expect(system.contains("Project Update / Milestone"))
        #expect(system.contains("Event / Long-Form Recap"))
        #expect(system.contains("Return ONE finished LinkedIn post only"))
        #expect(system.contains("2-3 highly relevant hashtags"))
        #expect(user.contains("Select the best POST TYPE TEMPLATE"))
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

}
