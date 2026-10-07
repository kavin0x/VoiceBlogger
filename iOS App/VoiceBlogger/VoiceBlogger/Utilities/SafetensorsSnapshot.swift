import Foundation

/// Decides whether a Hugging Face snapshot has a finished weight file.
/// A directory that only has `config.json` (or a truncated `model.safetensors`)
/// must not be loaded: MLX builds the network and then throws `keyNotFound`
/// for the first missing parameter.
enum SafetensorsSnapshot {
    static func isLoadable(_ directory: URL) -> Bool {
        let config = directory.appendingPathComponent("config.json").resolvingSymlinksInPath()
        guard fileSize(config) > 0 else { return false }

        let weights = weightFiles(in: directory)
        guard !weights.isEmpty, weights.allSatisfy(isCompleteFile) else { return false }

        let index = directory.appendingPathComponent("model.safetensors.index.json")
        guard FileManager.default.fileExists(atPath: index.path) else { return true }
        return indexAgrees(with: weights, index: index)
    }

    static func isCompleteFile(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        let size = fileSize(resolved)
        guard size > 8 else { return false }

        guard let handle = try? FileHandle(forReadingFrom: resolved) else { return false }
        defer { try? handle.close() }

        guard let lengthData = try? handle.read(upToCount: 8), lengthData.count == 8 else { return false }
        let headerLength = lengthData.withUnsafeBytes { $0.load(as: UInt64.self) }
        guard headerLength > 1, headerLength < 100_000_000 else { return false }
        guard size >= 8 + headerLength else { return false }

        guard let headerData = try? handle.read(upToCount: Int(headerLength)),
              headerData.count == Int(headerLength),
              let json = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any]
        else { return false }

        var maxEnd: UInt64 = 0
        var tensorCount = 0
        for (name, value) in json {
            if name == "__metadata__" { continue }
            guard let tensor = value as? [String: Any],
                  let offsets = tensor["data_offsets"] as? [Any],
                  offsets.count == 2,
                  let end = jsonUInt64(offsets[1])
            else { continue }
            tensorCount += 1
            if end > maxEnd { maxEnd = end }
        }
        guard tensorCount > 0 else { return false }
        return 8 + headerLength + maxEnd <= size
    }

    private static func weightFiles(in directory: URL) -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return files.filter { $0.pathExtension == "safetensors" }
    }

    private static func indexAgrees(with weights: [URL], index: URL) -> Bool {
        guard let data = try? Data(contentsOf: index),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }

        if let weightMap = json["weight_map"] as? [String: String] {
            let required = Set(weightMap.values)
            let present = Set(weights.map(\.lastPathComponent))
            guard required.isSubset(of: present) else { return false }
        }

        if let metadata = json["metadata"] as? [String: Any],
           let total = jsonUInt64(metadata["total_size"]),
           total > 0 {
            let bytes = weights.reduce(UInt64(0)) { $0 + fileSize($1.resolvingSymlinksInPath()) }
            // File bytes include the header, so a finished shard is larger than the tensor payload.
            guard bytes > total else { return false }
        }
        return true
    }

    private static func fileSize(_ url: URL) -> UInt64 {
        let resolved = url.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: resolved.path) else { return 0 }
        let size = (try? resolved.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return UInt64(size)
    }

    private static func jsonUInt64(_ value: Any?) -> UInt64? {
        (value as? NSNumber)?.uint64Value
    }
}

enum LLMNetworkRetry {
    /// One attempt plus three resumes. A cellular drop (-1005) should not end a multi-gigabyte download.
    static let maximumAttempts = 4

    static func load(
        progressHandler: (@Sendable (Foundation.Progress) -> Void)? = nil
    ) async throws -> LLMService {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                if await DownloadNetworkPolicy.blockedByWifiOnlySetting() {
                    throw DownloadBlockedOnCellularError()
                }
                return try await LLMService.make(progressHandler: progressHandler)
            } catch {
                guard shouldRetry(error, attempt: attempt) else { throw error }
                attempt += 1
                try await Task.sleep(for: .seconds(delaySeconds(afterFailure: attempt)))
            }
        }
    }

    static func shouldRetry(_ error: Error, attempt: Int) -> Bool {
        guard attempt + 1 < maximumAttempts else { return false }
        if error is CancellationError { return false }
        if error is LLMLoadError { return false }
        if error is DownloadBlockedOnCellularError { return false }
        if isIncompleteWeightError(error) { return false }
        return isTransientNetworkError(error)
    }

    static func delaySeconds(afterFailure attempt: Int) -> Double {
        Double(1 << min(attempt, 3))
    }

    static func isIncompleteWeightError(_ error: Error) -> Bool {
        if let validation = error as? ModelValidationError, case .missingModelArtifacts = validation {
            return true
        }
        return String(describing: error).contains("keyNotFound")
    }

    static func isTransientNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNetworkConnectionLost,
                 NSURLErrorTimedOut,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorSecureConnectionFailed,
                 NSURLErrorCannotParseResponse:
                return true
            default:
                break
            }
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isTransientNetworkError(underlying)
        }
        return false
    }
}
