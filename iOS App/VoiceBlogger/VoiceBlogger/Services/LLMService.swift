import Foundation
import MLX
import MLXLLM
import MLXLMCommon

// ModelContainer is Sendable (final class ModelContainer: Sendable in mlx-swift-lm)
final class LLMService: Sendable {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
        MLX.Memory.cacheLimit = 512 * 1024 * 1024
    }

    static func make() async throws -> LLMService {
        let c = try await LLMModelFactory.shared.loadContainer(
            from: HubDownloader(),
            using: HuggingFaceTokenizerLoader(),
            configuration: ModelConfiguration(id: kLLMModelID)
        )
        return LLMService(container: c)
    }

    // Uses the mlx-swift-lm 3.x AsyncStream<Generation> API.
    // Each yielded value is a text chunk from the .chunk(String) generation event.
    func generateStream(messages: [[String: String]]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task.detached { [container] in
                do {
                    try await container.perform { context in
                        let input = try await context.processor.prepare(
                            input: UserInput(messages: messages)
                        )
                        var params = GenerateParameters()
                        params.temperature = 0.7
                        params.maxTokens = 2048

                        let stream = try MLXLMCommon.generate(
                            input: input,
                            parameters: params,
                            context: context
                        )
                        for await generation in stream {
                            if case .chunk(let text) = generation {
                                continuation.yield(text)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func generateBlog(transcript: String) -> AsyncThrowingStream<String, Error> {
        generateStream(messages: PromptBuilder.blogMessages(transcript: transcript))
    }

    func generateInstagramCaptions(blogContent: String) -> AsyncThrowingStream<String, Error> {
        generateStream(messages: PromptBuilder.instagramMessages(blogContent: blogContent))
    }
}
