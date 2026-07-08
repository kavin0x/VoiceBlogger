import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import HuggingFace

// ModelContainer is Sendable (final class ModelContainer: Sendable in mlx-swift-lm)
private final class GenerationCancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var cancelHandler: (() -> Void)?
    nonisolated(unsafe) private var didCancel = false

    nonisolated init() {}

    nonisolated func setCancelHandler(_ handler: @escaping () -> Void) {
        lock.lock()
        if didCancel {
            lock.unlock()
            handler()
            return
        }
        cancelHandler = handler
        lock.unlock()
    }

    nonisolated func cancel() {
        lock.lock()
        didCancel = true
        let handler = cancelHandler
        cancelHandler = nil
        lock.unlock()
        handler?()
    }
}

final class LLMService: Sendable {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
        MLX.Memory.cacheLimit = DeviceRAMTier.current.mlxCacheLimitBytes
    }

    static func make(progressHandler: (@Sendable (Progress) -> Void)? = nil) async throws -> LLMService {
        let c = try await LLMModelFactory.shared.loadContainer(
            from: HubDownloader(),
            using: HuggingFaceTokenizerLoader(),
            configuration: ModelConfiguration(id: ModelIDs.llm),
            progressHandler: { progress in
                progressHandler?(progress)
            }
        )
        return LLMService(container: c)
    }

    // Resolve the local HuggingFace cache directory for the LLM without any network I/O.
    // Returns nil if the model hasn't been downloaded yet or the cache is in an unexpected state.
    static func localModelDirectory() -> URL? {
        guard let repoID = HuggingFace.Repo.ID(rawValue: ModelIDs.llm) else { return nil }
        let cache = HubCache.default

        // Primary path: use the HF cache ref to resolve the exact commit snapshot.
        if let commitHash = cache.resolveRevision(repo: repoID, kind: .model, ref: "main"),
           let directory = try? cache.snapshotPath(repo: repoID, kind: .model, commitHash: commitHash),
           directoryContainsFiles(directory) {
            return directory
        }

        // Fallback: the ref file may be missing (e.g. after an app update) even though
        // the snapshot files are fully on disk. Scan the snapshots directory directly and
        // return the first hash-named subdirectory that contains files.
        return localModelDirectoryByScanning()
    }

    private static func localModelDirectoryByScanning() -> URL? {
        let fm = FileManager.default
        // HubCache.default on sandboxed iOS uses Library/Caches/huggingface/hub.
        // The repo folder name replaces "/" with "--" and is prefixed by kind:
        // models--mlx-community--Qwen2.5-1.5B-Instruct-4bit/snapshots/<commitHash>/
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let repoFolderName = "models--" + ModelIDs.llm.replacingOccurrences(of: "/", with: "--")
        let snapshotsDir = caches
            .appendingPathComponent("huggingface/hub")
            .appendingPathComponent(repoFolderName)
            .appendingPathComponent("snapshots")

        guard let entries = try? fm.contentsOfDirectory(
            at: snapshotsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for entry in entries {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDir && directoryContainsFiles(entry) {
                return entry
            }
        }
        return nil
    }

    private static func directoryContainsFiles(_ directory: URL) -> Bool {
        let fm = FileManager.default
        // The HF cache stores model files as symlinks in snapshot dirs pointing to blobs.
        // We check fm.fileExists (which resolves symlinks) rather than isRegularFileKey
        // (which returns false for symlinks themselves on some OS versions).
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        for case let url as URL in enumerator {
            let vals = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            if vals?.isRegularFile == true || vals?.isSymbolicLink == true {
                return true
            }
        }
        return false
    }

    // Load from a directory that was already downloaded (e.g. by a prefetch task).
    // Skips network I/O — goes straight to weight deserialization.
    static func makeFromDirectory(_ directory: URL) async throws -> LLMService {
        let c = try await LLMModelFactory.shared.loadContainer(
            from: directory,
            using: HuggingFaceTokenizerLoader()
        )
        return LLMService(container: c)
    }

    // Uses the mlx-swift-lm 3.x AsyncStream<Generation> API.
    // Each yielded value is a text chunk from the .chunk(String) generation event.
    // nonisolated so this can be called from Task.detached contexts (e.g. generateBlogChunked).
    nonisolated func generateStream(
        messages: [[String: String]],
        maxTokens: Int = 2048,
        temperature: Float = 0.45,
        clearCacheWhenDone: Bool = true
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let cancellationBox = GenerationCancellationBox()
            let task = Task.detached(priority: .userInitiated) { [container] in
                do {
                    await Task.yield()
                    try await container.perform { context in
                        let input = try await context.processor.prepare(
                            input: UserInput(messages: messages, additionalContext: ["enable_thinking": false])
                        )
                        var params = GenerateParameters()
                        params.temperature = temperature
                        params.topP = 0.92
                        params.repetitionPenalty = 1.12
                        params.repetitionContextSize = 128
                        params.frequencyPenalty = 0.08
                        params.frequencyContextSize = 160
                        params.maxTokens = maxTokens

                        let iterator = try TokenIterator(
                            input: input,
                            model: context.model,
                            cache: nil,
                            parameters: params
                        )
                        let (stream, generationTask) = MLXLMCommon.generateTask(
                            promptTokenCount: input.text.tokens.size,
                            modelConfiguration: context.configuration,
                            tokenizer: context.tokenizer,
                            iterator: iterator
                        )
                        cancellationBox.setCancelHandler {
                            generationTask.cancel()
                        }

                        var shouldCancelGeneration = false
                        for await generation in stream {
                            if Task.isCancelled {
                                shouldCancelGeneration = true
                                break
                            }
                            if case .chunk(let text) = generation {
                                if case .terminated = continuation.yield(text) {
                                    shouldCancelGeneration = true
                                    break
                                }
                            }
                        }

                        if shouldCancelGeneration {
                            generationTask.cancel()
                        }
                        await generationTask.value
                        if clearCacheWhenDone {
                            MLX.Memory.clearCache()
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    cancellationBox.cancel()
                    if clearCacheWhenDone { MLX.Memory.clearCache() }
                    continuation.finish()
                } catch {
                    cancellationBox.cancel()
                    if clearCacheWhenDone { MLX.Memory.clearCache() }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                cancellationBox.cancel()
                task.cancel()
            }
        }
    }

    // Collects an entire generateStream call into a single String (no streaming to caller).
    // Used for intermediate chunk-summary passes in the chunked blog generation path.
    nonisolated private func collectStream(
        messages: [[String: String]],
        maxTokens: Int,
        temperature: Float = 0.25,
        clearCacheWhenDone: Bool = false
    ) async throws -> String {
        var result = ""
        for try await token in generateStream(
            messages: messages,
            maxTokens: maxTokens,
            temperature: temperature,
            clearCacheWhenDone: clearCacheWhenDone
        ) {
            try Task.checkCancellation()
            result += token
        }
        return result
    }

    func polishTranscript(_ transcript: String) async throws -> String {
        let messages: [[String: String]] = [
            ["role": "system", "content": """
            Clean up a voice transcript. Remove filler words and false starts. Fix punctuation and paragraph breaks.
            Do not add new facts. Return only the polished transcript.
            """],
            ["role": "user", "content": transcript]
        ]
        return try await collectStream(messages: messages, maxTokens: 800, temperature: 0.2, clearCacheWhenDone: false)
    }

    // Multi-pass path: summarise each chunk then synthesise into the detected content type.
    // onPhaseChange is called with a human-readable status string at each stage so the UI
    // can show progress (e.g. "Analyzing part 2 of 4...").
    private func generateContentChunked(
        transcript: String,
        contentKind: GeneratedContentKind,
        isSpeakerAnnotated: Bool,
        vocabularyTerms: [String],
        onPhaseChange: (@Sendable (String) -> Void)?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                do {
                    let chunks = PromptBuilder.splitIntoChunks(transcript)
                    var summaries: [String] = []
                    summaries.reserveCapacity(chunks.count)

                    if DeviceRAMTier.current == .ample && chunks.count > 1 {
                        summaries = try await self.mapChunksParallel(chunks, vocabularyTerms: vocabularyTerms)
                    } else {
                        for (index, chunk) in chunks.enumerated() {
                            try Task.checkCancellation()
                            onPhaseChange?("Analyzing part \(index + 1) of \(chunks.count)…")
                            let messages = PromptBuilder.chunkSummaryMessages(
                                for: chunk,
                                index: index,
                                of: chunks.count,
                                vocabularyTerms: vocabularyTerms
                            )
                            let summary = try await self.collectStream(messages: messages, maxTokens: 350)
                            summaries.append(summary)
                        }
                    }

                    try Task.checkCancellation()
                    onPhaseChange?("Writing \(contentKind.displayName.lowercased())...")

                    let synthesisMessages = PromptBuilder.synthesisMessages(
                        from: summaries,
                        contentKind: contentKind,
                        isSpeakerAnnotated: isSpeakerAnnotated
                    )
                    for try await token in self.generateStream(messages: synthesisMessages, maxTokens: 2048, temperature: 0.38, clearCacheWhenDone: true) {
                        try Task.checkCancellation()
                        if case .terminated = continuation.yield(token) { break }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    nonisolated private func mapChunksParallel(_ chunks: [String], vocabularyTerms: [String]) async throws -> [String] {
        var summaries = Array(repeating: "", count: chunks.count)
        let width = 2
        var index = 0
        while index < chunks.count {
            let end = min(index + width, chunks.count)
            try await withThrowingTaskGroup(of: (Int, String).self) { group in
                for i in index..<end {
                    group.addTask {
                        let messages = PromptBuilder.chunkSummaryMessages(
                            for: chunks[i],
                            index: i,
                            of: chunks.count,
                            vocabularyTerms: vocabularyTerms
                        )
                        let summary = try await self.collectStream(messages: messages, maxTokens: 350)
                        return (i, summary)
                    }
                }
                for try await (i, summary) in group {
                    summaries[i] = summary
                }
            }
            index = end
        }
        return summaries
    }

    func generateContent(
        transcript: String,
        contentKind: GeneratedContentKind,
        isSpeakerAnnotated: Bool = false,
        vocabularyTerms: [String] = [],
        onPhaseChange: (@Sendable (String) -> Void)? = nil
    ) -> AsyncThrowingStream<String, Error> {
        if PromptBuilder.needsChunking(transcript) {
            return generateContentChunked(
                transcript: transcript,
                contentKind: contentKind,
                isSpeakerAnnotated: isSpeakerAnnotated,
                vocabularyTerms: vocabularyTerms,
                onPhaseChange: onPhaseChange
            )
        }
        return generateStream(
            messages: PromptBuilder.contentMessages(
                transcript: transcript,
                contentKind: contentKind,
                isSpeakerAnnotated: isSpeakerAnnotated,
                vocabularyTerms: vocabularyTerms
            ),
            maxTokens: 2048,
            temperature: 0.38,
            clearCacheWhenDone: true
        )
    }

    func generateBlog(
        transcript: String,
        isSpeakerAnnotated: Bool = false,
        onPhaseChange: (@Sendable (String) -> Void)? = nil
    ) -> AsyncThrowingStream<String, Error> {
        generateContent(
            transcript: transcript,
            contentKind: .blogPost,
            isSpeakerAnnotated: isSpeakerAnnotated,
            onPhaseChange: onPhaseChange
        )
    }

    func generateInstagramCaptions(blogContent: String) -> AsyncThrowingStream<String, Error> {
        generateStream(messages: PromptBuilder.instagramMessages(blogContent: blogContent), maxTokens: 350)
    }

    func generateLinkedInPost(blogContent: String) -> AsyncThrowingStream<String, Error> {
        generateStream(messages: PromptBuilder.linkedinMessages(blogContent: blogContent), maxTokens: 650)
    }
}
