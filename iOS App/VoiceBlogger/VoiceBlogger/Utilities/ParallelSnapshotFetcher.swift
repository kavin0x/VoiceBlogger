import Foundation

/// Plans and downloads Hugging Face snapshots with several HTTP ranges per large file.
///
/// A single TCP connection leaves most of a fast link idle. Speech bundles are fetched
/// smallest-first so CoreML specialization of a finished bundle can run while the next
/// bundle is still downloading.
nonisolated enum ByteRangePlan {
    struct Chunk: Equatable, Sendable {
        var index: Int
        var start: Int64
        var length: Int64

        var endInclusive: Int64 { start + length - 1 }
    }

    static func chunks(
        fileSize: Int64,
        maxParts: Int,
        minimumChunkBytes: Int64 = 8 * 1024 * 1024
    ) -> [Chunk] {
        guard fileSize > 0 else { return [] }
        let cappedParts = max(1, maxParts)
        let partsBySize = Int((fileSize + minimumChunkBytes - 1) / minimumChunkBytes)
        let partCount = min(cappedParts, max(1, partsBySize))
        let base = fileSize / Int64(partCount)
        var remainder = fileSize % Int64(partCount)
        var start: Int64 = 0
        var chunks: [Chunk] = []
        chunks.reserveCapacity(partCount)
        for index in 0..<partCount {
            let extra: Int64 = remainder > 0 ? 1 : 0
            if remainder > 0 { remainder -= 1 }
            let length = base + extra
            chunks.append(Chunk(index: index, start: start, length: length))
            start += length
        }
        return chunks
    }
}

nonisolated enum SnapshotPathRules {
    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part != "." && part != ".."
        }
    }

    /// Directory of a CoreML bundle, relative to the repo root.
    /// `openai_whisper-small/TextDecoder.mlmodelc/weights/weight.bin`
    /// → `openai_whisper-small/TextDecoder.mlmodelc`
    static func coreMLBundleDirectory(relativePath: String) -> String? {
        let parts = relativePath.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(where: { $0.hasSuffix(".mlmodelc") }) else { return nil }
        return parts.prefix(index + 1).joined(separator: "/")
    }

    static func matches(path: String, globs: [String]) -> Bool {
        guard !globs.isEmpty else { return true }
        return globs.contains { fnmatch($0, path, 0) == 0 }
    }
}

nonisolated struct SnapshotFileEntry: Equatable, Sendable {
    var relativePath: String
    var size: Int64
}

nonisolated enum SnapshotSchedule {
    struct Bundle: Equatable, Sendable {
        var directory: String
        var files: [SnapshotFileEntry]

        var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
    }

    /// Loose files stay beside the bundles. Bundles are smallest-first so specialization
    /// of an earlier bundle overlaps the download of the next one.
    static func arrange(_ files: [SnapshotFileEntry]) -> (loose: [SnapshotFileEntry], bundles: [Bundle]) {
        var loose: [SnapshotFileEntry] = []
        var grouped: [String: [SnapshotFileEntry]] = [:]
        for file in files {
            if let directory = SnapshotPathRules.coreMLBundleDirectory(relativePath: file.relativePath) {
                grouped[directory, default: []].append(file)
            } else {
                loose.append(file)
            }
        }
        let bundles = grouped
            .map { Bundle(directory: $0.key, files: $0.value) }
            .sorted { lhs, rhs in
                if lhs.totalBytes == rhs.totalBytes { return lhs.directory < rhs.directory }
                return lhs.totalBytes < rhs.totalBytes
            }
        return (loose, bundles)
    }
}

nonisolated enum ModelSnapshotStore {
    static func llmSnapshotDirectory(repoID: String) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let safe = repoID.replacingOccurrences(of: "/", with: "--")
        return caches
            .appendingPathComponent("voiceblogger/llm-snapshots", isDirectory: true)
            .appendingPathComponent(safe, isDirectory: true)
    }
}

nonisolated enum ParallelFetchError: LocalizedError {
    case invalidRepository(String)
    case unsafePath(String)
    case rangeNotHonored
    case unexpectedStatus(Int)
    case shortWrite

    var errorDescription: String? {
        switch self {
        case .invalidRepository(let id):
            return "Invalid Hugging Face repository ID: '\(id)'"
        case .unsafePath(let path):
            return "Refusing to download '\(path)'."
        case .rangeNotHonored:
            return "The download server did not accept a partial transfer."
        case .unexpectedStatus(let code):
            return "Download failed with HTTP \(code)."
        case .shortWrite:
            return "The download ended before the file was complete."
        }
    }
}

/// Caps in-flight transfers across the speech and writing downloads.
nonisolated final class TransferPermits: @unchecked Sendable {
    static let shared = TransferPermits(limit: HubDownloadPolicy.maximumConcurrentTransfers)

    private let lock = NSLock()
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        available = max(1, limit)
    }

    func withPermit<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        await acquire()
        do {
            let value = try await body()
            signal()
            return value
        } catch {
            signal()
            throw error
        }
    }

    private func acquire() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if available > 0 {
                available -= 1
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    private func signal() {
        lock.lock()
        let waiter = waiters.isEmpty ? nil : waiters.removeFirst()
        if waiter == nil { available += 1 }
        lock.unlock()
        waiter?.resume()
    }
}

nonisolated final class SerialAsyncQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var tail: Task<Void, Never>?

    func enqueue(_ work: @escaping @Sendable () async -> Void) {
        lock.lock()
        let previous = tail
        let next = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await work()
        }
        tail = next
        lock.unlock()
    }

    func drain() async {
        await pendingTail()?.value
    }

    private func pendingTail() -> Task<Void, Never>? {
        lock.lock()
        defer { lock.unlock() }
        return tail
    }
}

nonisolated enum ParallelSnapshotFetcher {
    private struct TreeFile: Decodable {
        var path: String
        var type: String
        var size: Int?
    }

    static func download(
        repoID: String,
        revision: String,
        into destination: URL,
        pathPrefix: String?,
        globs: [String],
        progress: @escaping @Sendable (Double) -> Void,
        onBundleReady: (@Sendable (URL) -> Void)? = nil
    ) async throws {
        guard repoID.split(separator: "/").count == 2 else {
            throw ParallelFetchError.invalidRepository(repoID)
        }
        let session = makeSession()
        defer { session.finishTasksAndInvalidate() }

        let listed = try await listFiles(
            repoID: repoID,
            revision: revision,
            pathPrefix: pathPrefix,
            globs: globs,
            session: session
        )
        let schedule = SnapshotSchedule.arrange(listed)
        let totalBytes = listed.reduce(Int64(0)) { $0 + $1.size }
        let reporter = ProgressReporter(total: totalBytes, onFraction: progress)
        reporter.add(0)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await download(files: schedule.loose, repoID: repoID, revision: revision, into: destination, session: session, reporter: reporter)
            }
            group.addTask {
                for bundle in schedule.bundles {
                    try Task.checkCancellation()
                    try await download(files: bundle.files, repoID: repoID, revision: revision, into: destination, session: session, reporter: reporter)
                    onBundleReady?(appendingRelativePath(destination, bundle.directory))
                }
            }
            try await group.waitForAll()
        }
        progress(1)
    }

    private static func download(
        files: [SnapshotFileEntry],
        repoID: String,
        revision: String,
        into destination: URL,
        session: URLSession,
        reporter: ProgressReporter
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for file in files {
                group.addTask {
                    try await downloadFile(
                        file,
                        repoID: repoID,
                        revision: revision,
                        into: destination,
                        session: session,
                        reporter: reporter
                    )
                }
            }
            try await group.waitForAll()
        }
    }

    private static func downloadFile(
        _ file: SnapshotFileEntry,
        repoID: String,
        revision: String,
        into destination: URL,
        session: URLSession,
        reporter: ProgressReporter
    ) async throws {
        try Task.checkCancellation()
        guard SnapshotPathRules.isSafeRelativePath(file.relativePath) else {
            throw ParallelFetchError.unsafePath(file.relativePath)
        }
        let output = appendingRelativePath(destination, file.relativePath)
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: output.path),
           fileSize(output) == file.size,
           !FileManager.default.fileExists(atPath: sidecarURL(for: output).path) {
            reporter.add(file.size)
            return
        }

        let remote = fileURL(repoID: repoID, revision: revision, relativePath: file.relativePath)
        let chunks = ByteRangePlan.chunks(
            fileSize: file.size,
            maxParts: HubDownloadPolicy.rangedTransferParts
        )
        if chunks.count <= 1 {
            try await TransferPermits.shared.withPermit {
                try await downloadSingle(remote: remote, to: output, session: session)
            }
            reporter.add(file.size)
            return
        }

        let sidecar = sidecarURL(for: output)
        var completed = loadCompletedChunks(at: sidecar)
        if completed.isEmpty {
            // Write the sidecar before extending the file. A preallocated file
            // has the final size, so size alone cannot mean "finished".
            storeCompletedChunks([], at: sidecar, fileSize: file.size)
        }
        if !FileManager.default.fileExists(atPath: output.path) || fileSize(output) != file.size {
            FileManager.default.createFile(atPath: output.path, contents: nil)
            let fd = try openFile(output)
            defer { close(fd) }
            guard ftruncate(fd, off_t(file.size)) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
        for chunk in chunks where completed.contains(chunk.index) {
            reporter.add(chunk.length)
        }

        let fd = try openFile(output)
        defer { close(fd) }
        try await withThrowingTaskGroup(of: Int.self) { group in
            for chunk in chunks where !completed.contains(chunk.index) {
                group.addTask {
                    try await TransferPermits.shared.withPermit {
                        try await downloadChunk(chunk, remote: remote, fd: fd, session: session)
                    }
                    return chunk.index
                }
            }
            for try await index in group {
                completed.insert(index)
                storeCompletedChunks(completed, at: sidecar, fileSize: file.size)
                if let chunk = chunks.first(where: { $0.index == index }) {
                    reporter.add(chunk.length)
                }
            }
        }
        try? FileManager.default.removeItem(at: sidecar)
    }

    private static func listFiles(
        repoID: String,
        revision: String,
        pathPrefix: String?,
        globs: [String],
        session: URLSession
    ) async throws -> [SnapshotFileEntry] {
        var url = URL(string: "https://huggingface.co/api/models")!
        for part in repoID.split(separator: "/") {
            url.append(path: String(part))
        }
        url.append(path: "tree")
        url.append(path: revision)
        if let pathPrefix {
            for part in pathPrefix.split(separator: "/") where !part.isEmpty {
                url.append(path: String(part))
            }
        }
        url.append(queryItems: [URLQueryItem(name: "recursive", value: "true")])

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ParallelFetchError.unexpectedStatus(http.statusCode)
        }
        let decoded = try JSONDecoder().decode([TreeFile].self, from: data)
        var files: [SnapshotFileEntry] = []
        for entry in decoded where entry.type == "file" {
            guard SnapshotPathRules.isSafeRelativePath(entry.path) else {
                throw ParallelFetchError.unsafePath(entry.path)
            }
            if let pathPrefix, !entry.path.hasPrefix(pathPrefix + "/"), entry.path != pathPrefix {
                continue
            }
            guard SnapshotPathRules.matches(path: entry.path, globs: globs) else { continue }
            files.append(SnapshotFileEntry(relativePath: entry.path, size: Int64(entry.size ?? 0)))
        }
        return files
    }

    private static func downloadSingle(remote: URL, to output: URL, session: URLSession) async throws {
        var request = URLRequest(url: remote)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let (temp, response) = try await session.download(for: request, delegate: ChunkTaskDelegate())
        try validateHTTP(response, allowingRange: false)
        try replaceItem(at: output, with: temp)
    }

    private static func downloadChunk(
        _ chunk: ByteRangePlan.Chunk,
        remote: URL,
        fd: Int32,
        session: URLSession
    ) async throws {
        var lastError: Error = ParallelFetchError.rangeNotHonored
        for attempt in 0..<3 {
            try Task.checkCancellation()
            do {
                var request = URLRequest(url: remote)
                request.setValue("bytes=\(chunk.start)-\(chunk.endInclusive)", forHTTPHeaderField: "Range")
                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                let (temp, response) = try await session.download(for: request, delegate: ChunkTaskDelegate())
                do {
                    try validateHTTP(response, allowingRange: true)
                    let received = fileSize(temp)
                    guard received == chunk.length else { throw ParallelFetchError.shortWrite }
                    try write(fd: fd, from: temp, at: chunk.start)
                    try? FileManager.default.removeItem(at: temp)
                    return
                } catch {
                    try? FileManager.default.removeItem(at: temp)
                    throw error
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt < 2 {
                    try await Task.sleep(for: .milliseconds(400 * (attempt + 1)))
                }
            }
        }
        throw lastError
    }

    private static func validateHTTP(_ response: URLResponse, allowingRange: Bool) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ParallelFetchError.unexpectedStatus(-1)
        }
        if allowingRange {
            guard http.statusCode == 206 else {
                if http.statusCode == 200 { throw ParallelFetchError.rangeNotHonored }
                throw ParallelFetchError.unexpectedStatus(http.statusCode)
            }
        } else if !(200..<300).contains(http.statusCode) {
            throw ParallelFetchError.unexpectedStatus(http.statusCode)
        }
    }

    private static func write(fd: Int32, from temp: URL, at offset: Int64) throws {
        let source = try FileHandle(forReadingFrom: temp)
        defer { try? source.close() }
        var written: Int64 = 0
        while true {
            let data = try source.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            try data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                var remaining = raw.count
                var cursor = base
                var dest = off_t(offset + written)
                while remaining > 0 {
                    let wrote = pwrite(fd, cursor, remaining, dest)
                    if wrote < 0 {
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                    remaining -= wrote
                    cursor = cursor.advanced(by: wrote)
                    dest += off_t(wrote)
                    written += Int64(wrote)
                }
            }
        }
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = HubDownloadPolicy.maximumConcurrentTransfers
        config.httpShouldUsePipelining = true
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 60 * 60
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = true
        config.networkServiceType = .responsiveData
        config.httpAdditionalHeaders = ["Accept-Encoding": "identity"]
        HubDownloadPolicy.applyNetworkAccess(
            to: config,
            wifiOnly: UserDefaults.standard.bool(forKey: HubDownloadPolicy.wifiOnlyDefaultsKey)
        )
        return URLSession(configuration: config)
    }

    private static func fileURL(repoID: String, revision: String, relativePath: String) -> URL {
        var url = URL(string: "https://huggingface.co")!
        for part in repoID.split(separator: "/") {
            url.append(path: String(part))
        }
        url.append(path: "resolve")
        url.append(path: revision)
        for part in relativePath.split(separator: "/") {
            url.append(path: String(part))
        }
        return url
    }

    static func appendingRelativePath(_ base: URL, _ relative: String) -> URL {
        var url = base
        for part in relative.split(separator: "/") {
            url.append(path: String(part))
        }
        return url
    }

    private static func sidecarURL(for file: URL) -> URL {
        file.appendingPathExtension("vbchunks")
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return Int64(size)
    }

    private static func openFile(_ url: URL) throws -> Int32 {
        let fd = url.path.withCString { open($0, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR) }
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return fd
    }

    private struct ChunkSidecar: Codable {
        var fileSize: Int64
        var completed: [Int]
    }

    private static func loadCompletedChunks(at url: URL) -> Set<Int> {
        guard let data = try? Data(contentsOf: url),
              let sidecar = try? JSONDecoder().decode(ChunkSidecar.self, from: data) else { return [] }
        return Set(sidecar.completed)
    }

    private static func storeCompletedChunks(_ completed: Set<Int>, at url: URL, fileSize: Int64) {
        let sidecar = ChunkSidecar(fileSize: fileSize, completed: completed.sorted())
        guard let data = try? JSONEncoder().encode(sidecar) else { return }
        let temp = url.appendingPathExtension("tmp")
        try? data.write(to: temp, options: .atomic)
        _ = try? FileManager.default.replaceItemAt(url, withItemAt: temp)
    }

    private static func replaceItem(at destination: URL, with temp: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: destination)
        }
    }
}

private nonisolated final class ProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var done: Int64 = 0
    private let total: Int64
    private var lastReport = Date.distantPast
    private let onFraction: @Sendable (Double) -> Void

    init(total: Int64, onFraction: @escaping @Sendable (Double) -> Void) {
        self.total = total
        self.onFraction = onFraction
    }

    func add(_ bytes: Int64) {
        lock.lock()
        done += bytes
        let fraction = total > 0 ? min(1, Double(done) / Double(total)) : 1
        let now = Date()
        let shouldReport = fraction >= 1 || now.timeIntervalSince(lastReport) >= 0.2
        if shouldReport { lastReport = now }
        lock.unlock()
        if shouldReport { onFraction(fraction) }
    }
}

private nonisolated final class ChunkTaskDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var redirected = request
        if let range = task.originalRequest?.value(forHTTPHeaderField: "Range") {
            redirected.setValue(range, forHTTPHeaderField: "Range")
        }
        redirected.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        completionHandler(redirected)
    }
}
