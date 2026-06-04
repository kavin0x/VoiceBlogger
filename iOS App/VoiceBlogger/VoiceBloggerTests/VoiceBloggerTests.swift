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

}
