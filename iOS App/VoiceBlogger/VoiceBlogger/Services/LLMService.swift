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
            configuration: ModelConfiguration(id: kLLMModelID),
            progressHandler: { progress in
                progressHandler?(progress)
            }
        )
        return LLMService(container: c)
    }

    // Resolve the local HuggingFace cache directory for the LLM without any network I/O.
    // Returns nil if the model hasn't been downloaded yet or the cache is in an unexpected state.
    static func localModelDirectory() -> URL? {
        guard let repoID = HuggingFace.Repo.ID(rawValue: kLLMModelID) else { return nil }
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
        let repoFolderName = "models--" + kLLMModelID.replacingOccurrences(of: "/", with: "--")
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
    nonisolated func generateStream(messages: [[String: String]], maxTokens: Int = 2048) -> AsyncThrowingStream<String, Error> {
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
                        params.temperature = 0.45
                        params.topP = 0.9
                        params.repetitionPenalty = 1.15
                        params.repetitionContextSize = 96
                        params.frequencyPenalty = 0.05
                        params.frequencyContextSize = 128
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
                        MLX.Memory.clearCache()
                    }
                    continuation.finish()
                } catch is CancellationError {
                    cancellationBox.cancel()
                    MLX.Memory.clearCache()
                    continuation.finish()
                } catch {
                    cancellationBox.cancel()
                    MLX.Memory.clearCache()
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
    nonisolated private func collectStream(messages: [[String: String]], maxTokens: Int) async throws -> String {
        var result = ""
        for try await token in generateStream(messages: messages, maxTokens: maxTokens) {
            try Task.checkCancellation()
            result += token
        }
        return result
    }

    // Multi-pass path: summarise each chunk then synthesise into the detected content type.
    // onPhaseChange is called with a human-readable status string at each stage so the UI
    // can show progress (e.g. "Analyzing part 2 of 4...").
    private func generateContentChunked(
        transcript: String,
        contentKind: GeneratedContentKind,
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

                    for (index, chunk) in chunks.enumerated() {
                        try Task.checkCancellation()
                        onPhaseChange?("Analyzing part \(index + 1) of \(chunks.count)…")
                        let messages = PromptBuilder.chunkSummaryMessages(for: chunk, index: index, of: chunks.count)
                        let summary = try await self.collectStream(messages: messages, maxTokens: 400)
                        summaries.append(summary)
                    }

                    try Task.checkCancellation()
                    onPhaseChange?("Writing \(contentKind.displayName.lowercased())...")

                    let synthesisMessages = PromptBuilder.synthesisMessages(from: summaries, contentKind: contentKind)
                    for try await token in self.generateStream(messages: synthesisMessages, maxTokens: 1800) {
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

    func generateContent(
        transcript: String,
        contentKind: GeneratedContentKind,
        onPhaseChange: (@Sendable (String) -> Void)? = nil
    ) -> AsyncThrowingStream<String, Error> {
        if PromptBuilder.needsChunking(transcript) {
            return generateContentChunked(
                transcript: transcript,
                contentKind: contentKind,
                onPhaseChange: onPhaseChange
            )
        }
        return generateStream(
            messages: PromptBuilder.contentMessages(transcript: transcript, contentKind: contentKind),
            maxTokens: 1800
        )
    }

    func generateBlog(
        transcript: String,
        onPhaseChange: (@Sendable (String) -> Void)? = nil
    ) -> AsyncThrowingStream<String, Error> {
        generateContent(
            transcript: transcript,
            contentKind: .blogPost,
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
