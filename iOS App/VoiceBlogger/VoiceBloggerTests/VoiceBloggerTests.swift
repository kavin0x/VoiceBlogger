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

    @Test func blogGenerationHandoffRequiresTranscriptAndIdleState() {
        #expect(BlogGenerationHandoff.canGenerateBlog(from: "Transcript", isBusy: false))
        #expect(!BlogGenerationHandoff.canGenerateBlog(from: "   \n", isBusy: false))
        #expect(!BlogGenerationHandoff.canGenerateBlog(from: "Transcript", isBusy: true))
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

}
