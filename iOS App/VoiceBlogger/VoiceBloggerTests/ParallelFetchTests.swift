import Foundation
import Testing
@testable import VoiceBlogger

struct ParallelFetchTests {
    @Test func byteRangesCoverTheFileWithoutGaps() {
        let chunks = ByteRangePlan.chunks(fileSize: 100, maxParts: 4, minimumChunkBytes: 10)
        #expect(chunks.map(\.length).reduce(0, +) == 100)
        #expect(chunks.first?.start == 0)
        var cursor: Int64 = 0
        for chunk in chunks {
            #expect(chunk.start == cursor)
            cursor += chunk.length
        }
        #expect(cursor == 100)
    }

    @Test func smallFileStaysOneRange() {
        let chunks = ByteRangePlan.chunks(fileSize: 1000, maxParts: 6, minimumChunkBytes: 8 * 1024 * 1024)
        #expect(chunks.count == 1)
        #expect(chunks[0].length == 1000)
    }

    @Test func largeFileUsesThePartCap() {
        let chunks = ByteRangePlan.chunks(fileSize: 900_000_000, maxParts: 6, minimumChunkBytes: 8 * 1024 * 1024)
        #expect(chunks.count == 6)
        #expect(chunks.map(\.length).reduce(0, +) == 900_000_000)
    }

    @Test func unsafePathsAreRejected() {
        #expect(!SnapshotPathRules.isSafeRelativePath("../weights.bin"))
        #expect(!SnapshotPathRules.isSafeRelativePath("/tmp/weights.bin"))
        #expect(!SnapshotPathRules.isSafeRelativePath("foo/../../weights.bin"))
        #expect(SnapshotPathRules.isSafeRelativePath("openai_whisper-small/config.json"))
    }

    @Test func coreMLBundleDirectoryStopsAtTheBundle() {
        let path = "openai_whisper-small/TextDecoder.mlmodelc/weights/weight.bin"
        #expect(SnapshotPathRules.coreMLBundleDirectory(relativePath: path) == "openai_whisper-small/TextDecoder.mlmodelc")
        #expect(SnapshotPathRules.coreMLBundleDirectory(relativePath: "openai_whisper-small/config.json") == nil)
    }

    @Test func smallerBundlesDownloadFirst() {
        let files = [
            SnapshotFileEntry(relativePath: "m/AudioEncoder.mlmodelc/weights/weight.bin", size: 500),
            SnapshotFileEntry(relativePath: "m/MelSpectrogram.mlmodelc/weights/weight.bin", size: 10),
            SnapshotFileEntry(relativePath: "m/config.json", size: 1),
            SnapshotFileEntry(relativePath: "m/TextDecoder.mlmodelc/weights/weight.bin", size: 200),
        ]
        let schedule = SnapshotSchedule.arrange(files)
        #expect(schedule.loose.map(\.relativePath) == ["m/config.json"])
        #expect(schedule.bundles.map(\.directory) == [
            "m/MelSpectrogram.mlmodelc",
            "m/TextDecoder.mlmodelc",
            "m/AudioEncoder.mlmodelc",
        ])
    }
}
