import Foundation

/// Hops model load and inference off the main actor.
///
/// This target defaults every type to the main actor, and approachable concurrency
/// keeps a normal `await` on that actor. Weight loads and Whisper decoding then
/// freeze the UI, so streaming text never gets a chance to draw.
nonisolated enum OffMain {
    nonisolated static func run<T>(
        priority: TaskPriority = .userInitiated,
        _ work: @escaping () async throws -> T
    ) async throws -> T {
        nonisolated(unsafe) let work = work
        let boxed = try await Task.detached(priority: priority) {
            do {
                return UncheckedSendBox<Result<T, any Error>>(.success(try await work()))
            } catch {
                return UncheckedSendBox<Result<T, any Error>>(.failure(error))
            }
        }.value
        return try boxed.value.get()
    }

    nonisolated static func leavesMainThread() async -> Bool {
        await Task.detached { Thread.isMainThread }.value
    }
}

private nonisolated final class UncheckedSendBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// Joins Whisper's per-window callbacks into one growing transcript.
/// Each callback replaces only that window; earlier windows stay put.
nonisolated final class StreamingTranscriptAssembler: @unchecked Sendable {
    private let lock = NSLock()
    private var windows: [Int: String] = [:]

    nonisolated func apply(windowId: Int, text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }
        if !cleaned.isEmpty {
            windows[windowId] = cleaned
        }
        return windows.keys.sorted()
            .compactMap { windows[$0] }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
