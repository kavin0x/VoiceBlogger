import Foundation
import MLXLMCommon
import HuggingFace
import Tokenizers

// Adapts HuggingFace.HubClient to the MLXLMCommon.Downloader protocol.
// Equivalent to what the #hubDownloader() macro expands to.
struct HubDownloader: MLXLMCommon.Downloader {
    private let upstream: HuggingFace.HubClient

    init(_ upstream: HuggingFace.HubClient = HubDownloader.makeClient()) {
        self.upstream = upstream
    }

    private static func makeClient() -> HuggingFace.HubClient {
        let config = URLSessionConfiguration.default
        // Max connections per host — HF's CDN is multi-host (CDN redirects), so iOS enforces
        // this per resolved IP. Keep this high enough to saturate bandwidth across shards.
        config.httpMaximumConnectionsPerHost = 24
        // Per-packet idle timeout — large shards can stall 60-120s between TCP retries on
        // a flaky link before the next chunk arrives. 300s prevents spurious -1001 kills.
        config.timeoutIntervalForRequest = 300
        // No wall-clock cap on total download duration.
        config.timeoutIntervalForResource = .infinity
        // Disable local disk cache — model files are already persisted by HubClient's own
        // cache; URLCache just wastes memory and slows the pipeline.
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.waitsForConnectivity = true
        config.networkServiceType = .responsiveData
        config.httpAdditionalHeaders = ["Accept-Encoding": "br, gzip, deflate"]
        // Allow downloads over cellular as well as Wi-Fi.
        config.allowsCellularAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        return HubClient(session: URLSession(configuration: config))
    }

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Foundation.Progress) -> Void
    ) async throws -> URL {
        guard let repoID = HuggingFace.Repo.ID(rawValue: id) else {
            throw HubDownloaderError.invalidRepositoryID(id)
        }
        // Match httpMaximumConnectionsPerHost so every slot can be used simultaneously.
        return try await upstream.downloadSnapshot(
            of: repoID,
            revision: revision ?? "main",
            matching: patterns,
            maxConcurrentDownloads: 24,
            progressHandler: { @MainActor progress in progressHandler(progress) }
        )
    }
}

enum HubDownloaderError: LocalizedError {
    case invalidRepositoryID(String)
    var errorDescription: String? {
        if case .invalidRepositoryID(let id) = self {
            return "Invalid Hugging Face repository ID: '\(id)'"
        }
        return nil
    }
}

// Adapts Tokenizers.AutoTokenizer to the MLXLMCommon.TokenizerLoader protocol.
// Equivalent to what the #huggingFaceTokenizerLoader() macro expands to.
struct HuggingFaceTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
        return HuggingFaceTokenizerBridge(upstream)
    }
}

private struct HuggingFaceTokenizerBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
