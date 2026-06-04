import Foundation
import MLX
import MLXLLM
import MLXLMCommon

// ModelContainer is Sendable (final class ModelContainer: Sendable in mlx-swift-lm)
final class LLMService: Sendable {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
        MLX.Memory.cacheLimit = 768 * 1024 * 1024
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

    // Uses the mlx-swift-lm 3.x AsyncStream<Generation> API.
    // Each yielded value is a text chunk from the .chunk(String) generation event.
    func generateStream(messages: [[String: String]], maxTokens: Int = 1024) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [container] in
                do {
                    try await container.perform { context in
                        let input = try await context.processor.prepare(
                            input: UserInput(messages: messages)
                        )
                        var params = GenerateParameters()
                        params.temperature = 0.7
                        params.maxTokens = maxTokens

                        MLX.Memory.clearCache()

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
                        for await generation in stream {
                            if Task.isCancelled { break }
                            if case .chunk(let text) = generation {
                                if case .terminated = continuation.yield(text) {
                                    break
                                }
                            }
                        }
                        await generationTask.value
                        MLX.Memory.clearCache()
                    }
                    continuation.finish()
                } catch is CancellationError {
                    MLX.Memory.clearCache()
                    continuation.finish()
                } catch {
                    MLX.Memory.clearCache()
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func generateBlog(transcript: String) -> AsyncThrowingStream<String, Error> {
        generateStream(messages: PromptBuilder.blogMessages(transcript: transcript), maxTokens: 1024)
    }

    func generateInstagramCaptions(blogContent: String) -> AsyncThrowingStream<String, Error> {
        generateStream(messages: PromptBuilder.instagramMessages(blogContent: blogContent), maxTokens: 450)
    }
}
