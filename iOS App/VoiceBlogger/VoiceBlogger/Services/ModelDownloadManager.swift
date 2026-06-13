import Foundation
import Observation
import CoreML
import WhisperKit
import MLX
import MLXLLM
import MLXLMCommon

let kLLMModelID = "mlx-community/Qwen3.5-2B-MLX-4bit"
let kWhisperModelID = "openai_whisper-medium"

private let kWhisperReadyKey = "whisperModelReady_v4"
private let kLLMReadyKey = "llmModelReady_v3"

@MainActor
@Observable
final class ModelDownloadManager {
    var whisperProgress: Double = 0
    var llmProgress: Double = 0
    var isWhisperReady: Bool
    var isLLMReady: Bool
    var downloadError: String?
    var isDownloading = false

    // Retained after download so TranscriptionService can reuse it without reloading from disk.
    @ObservationIgnored var whisperKit: WhisperKit?
    @ObservationIgnored private var whisperWarmTask: Task<Void, Never>?

    // Retained so BlogView and InstagramView share one loaded instance — loading it twice OOMs.
    @ObservationIgnored var llmService: LLMService?
    @ObservationIgnored private var llmLoadTask: Task<LLMService, Error>?

    // Tracks whether MLX's C++ allocator was initialized this process session. Once the LLM loads,
    // MLX initializes its Metal allocator; subsequent clearCache() calls are safe. Before that,
    // clearCache() constructs a std::string from a null device pointer, crashing on iOS 27's
    // libc++ hardening assertion. Unlike isLLMReady (persisted to UserDefaults), this flag is
    // false at every cold start until the LLM actually loads.
    @ObservationIgnored private var mlxWasInitializedThisSession = false

    var allModelsReady: Bool { isWhisperReady && isLLMReady }
    var hasLoadedLLMService: Bool { llmService != nil }

    init() {
        isWhisperReady = UserDefaults.standard.bool(forKey: kWhisperReadyKey)
        isLLMReady = UserDefaults.standard.bool(forKey: kLLMReadyKey)
        if isWhisperReady { whisperProgress = 1.0 }
        if isLLMReady { llmProgress = 1.0 }
    }

    func warmWhisper() async {
        // Require allModelsReady: whisper must not load while the LLM is being downloaded,
        // as holding both in memory simultaneously (~1.5 GB) exceeds the device budget.
        // Require llmService == nil: if the LLM is already loaded (e.g. right after initial
        // download), defer whisper warm until the LLM is released to avoid the same OOM.
        guard allModelsReady, llmService == nil, llmLoadTask == nil, whisperKit == nil, whisperWarmTask == nil else { return }

        // Guard: if model files were deleted (e.g. simulator sandbox reset) but UserDefaults
        // still says ready, reset the flag so we don't pass a null path into WhisperKit's C++ layer.
        // WhisperKit uses HubApiWrapper which defaults to {documents}/huggingface/ as the download
        // base, so models land at {documents}/huggingface/models/argmaxinc/whisperkit-coreml/{modelID}/.
        let fm = FileManager.default
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let whisperModelDir = docs
                .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
                .appendingPathComponent(kWhisperModelID)
            if !fm.fileExists(atPath: whisperModelDir.path(percentEncoded: false)) {
                isWhisperReady = false
                UserDefaults.standard.removeObject(forKey: kWhisperReadyKey)
            }
            let hfDir = docs.appendingPathComponent("huggingface")
            if !fm.fileExists(atPath: hfDir.path(percentEncoded: false)) {
                isLLMReady = false
                UserDefaults.standard.removeObject(forKey: kLLMReadyKey)
            }
        }
        guard isWhisperReady else { return }

        let task = Task { [weak self] in
            guard let self else { return }
            let config = WhisperKitConfig(
                model: kWhisperModelID,
                computeOptions: ModelComputeOptions(
                    audioEncoderCompute: .cpuAndGPU,
                    textDecoderCompute: .cpuAndGPU
                )
            )
            guard !Task.isCancelled, let kit = try? await WhisperKit(config) else { return }
            guard !Task.isCancelled else { return }
            try? await kit.loadModels()
            guard !Task.isCancelled else {
                await kit.unloadModels()
                return
            }
            await MainActor.run { [weak self] in
                guard let self, self.whisperKit == nil, self.llmService == nil, self.llmLoadTask == nil else { return }
                self.whisperKit = kit
                self.whisperWarmTask = nil
            }
        }
        whisperWarmTask = task
        await task.value
        whisperWarmTask = nil
    }

    func downloadAll() async {
        guard !allModelsReady else { return }
        isDownloading = true
        downloadError = nil

        if !isWhisperReady {
            // Prefetch LLM files to disk concurrently with the whisper download.
            // resolve() is pure network→disk: it holds zero RAM, so running it alongside
            // whisper is safe. Only the subsequent _load() step (loadContainer(from:directory))
            // pulls weights into memory, and that is deferred until after whisper unloads.
            let prefetchTask = Task.detached(priority: .utility) { [weak self] in
                return try? await resolve(
                    configuration: ModelConfiguration(id: kLLMModelID),
                    from: HubDownloader(),
                    useLatest: false,
                    progressHandler: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            guard let self, !self.isLLMReady else { return }
                            let real = max(0.05, min(progress.fractionCompleted, 0.95))
                            if real > self.llmProgress {
                                self.llmProgress = real
                            }
                        }
                    }
                )
            }
            await downloadWhisper()

            if downloadError == nil {
                // Release whisper from RAM before loading the LLM — holding both
                // (~1.5 GB total) kills the process.
                await prepareForLLMGenerationBarrier()
                let prefetchedDir = await prefetchTask.value
                await downloadLLM(prefetchedDirectory: prefetchedDir?.modelDirectory)
            } else {
                prefetchTask.cancel()
            }
        } else if !isLLMReady {
            await downloadLLM(prefetchedDirectory: nil)
        }

        isDownloading = false
    }

    private func downloadErrorMessage(_ error: Error, for model: String) -> String {
        func isStallError(_ e: Error) -> Bool {
            let ns = e as NSError
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorTimedOut { return true }
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error { return isStallError(underlying) }
            return false
        }
        // NSURLErrorNetworkConnectionLost means the TCP connection was reset mid-transfer
        // (e.g. server-side RST). This is distinct from being offline.
        func isConnectionResetError(_ e: Error) -> Bool {
            let ns = e as NSError
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorNetworkConnectionLost { return true }
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error { return isConnectionResetError(underlying) }
            return false
        }
        func isOfflineError(_ e: Error) -> Bool {
            let ns = e as NSError
            if ns.domain == NSURLErrorDomain && [
                NSURLErrorNotConnectedToInternet,
                NSURLErrorCannotConnectToHost,
                NSURLErrorCannotFindHost,
                NSURLErrorDNSLookupFailed
            ].contains(ns.code) { return true }
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error { return isOfflineError(underlying) }
            return false
        }
        if isStallError(error) {
            return "Download stalled. Check your connection and tap Retry."
        }
        if isConnectionResetError(error) {
            return "Connection was interrupted mid-download. Tap Retry to resume."
        }
        if isOfflineError(error) {
            return "No internet connection. Connect to Wi-Fi or cellular and tap Retry."
        }
        return "\(model): \(error.localizedDescription)"
    }

    private func downloadWhisper() async {
        do {
            whisperProgress = 0.05
            // WhisperKit doesn't expose a progress callback through WhisperKitConfig, so
            // use a two-phase init: download-only first (load: false), then set the
            // modelStateCallback before calling loadModels() so UI sees loading progress.
            let config = WhisperKitConfig(
                model: kWhisperModelID,
                computeOptions: ModelComputeOptions(
                    audioEncoderCompute:  .cpuAndGPU,
                    textDecoderCompute: .cpuAndGPU
                ),
                load: false
            )
            // Phase 1: download model files (~80% of total time). No callback available here,
            // so animate progress smoothly to 0.45 while we wait.
            // ~0.002/tick at 1s → 0.45 over ~4 min for ~800 MB Whisper model on slow connections.
            let progressTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, !self.isWhisperReady, !Task.isCancelled else { return }
                    let next = min(self.whisperProgress + 0.002, 0.45)
                    if next > self.whisperProgress {
                        self.whisperProgress = next
                    }
                }
            }
            defer { progressTask.cancel() }
            let kit = try await WhisperKit(config)
            progressTask.cancel()

            // Phase 2: load CoreML models into memory — observable via modelStateCallback.
            whisperProgress = 0.5
            kit.modelStateCallback = { [weak self] _, newState in
                Task { @MainActor [weak self] in
                    guard let self, !self.isWhisperReady else { return }
                    switch newState {
                    case .loading:    self.whisperProgress = 0.6
                    case .prewarming: self.whisperProgress = 0.8
                    case .prewarmed:  self.whisperProgress = 0.9
                    case .loaded:     self.whisperProgress = 0.95
                    default: break
                    }
                }
            }
            try await kit.loadModels()
            kit.modelStateCallback = nil

            whisperKit = kit
            whisperProgress = 1.0
            isWhisperReady = true
            UserDefaults.standard.set(true, forKey: kWhisperReadyKey)
        } catch {
            downloadError = downloadErrorMessage(error, for: "Speech Recognition")
        }
    }

    private func downloadLLM(prefetchedDirectory: URL?) async {
        // MLX's Metal device constructor calls device.name.UTF8String in C++, which returns
        // nullptr on the iOS 27 simulator, crashing the hardened libc++ string constructor.
        // MLX requires real GPU hardware and is not supported on simulator.
        #if targetEnvironment(simulator)
        downloadError = "The AI Blog Generator requires a physical iPhone or iPad — the iOS Simulator is not supported."
        #else
        do {
            // If prefetchedDirectory is set, files are already on disk — skip straight to loading.
            // Otherwise download + load in one pass (the original path, used when whisper was
            // already ready on launch so no prefetch task was started).
            let progressHandler: @Sendable (Foundation.Progress) -> Void = { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // Cap at 0.95: loadContainer has two phases — download (reported here) and
                    // weight deserialization (silent). Allowing 1.0 here causes the bar to show
                    // 100% for several seconds while the device finishes loading, with no green.
                    // The bar snaps to 1.0 + green only when isLLMReady flips true.
                    let real = max(0.05, min(progress.fractionCompleted, 0.95))
                    if real > self.llmProgress {
                        self.llmProgress = real
                    }
                }
            }

            // Animation keeps the bar creeping during the silent weight-deserialization phase.
            // Caps at 0.97 so the final snap to 1.0 comes only from isLLMReady flipping.
            let animTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, !self.isLLMReady, !Task.isCancelled else { return }
                    let next = min(self.llmProgress + 0.004, 0.97)
                    if next > self.llmProgress {
                        self.llmProgress = next
                    }
                }
            }

            let service: LLMService = try await withThrowingTaskGroup(of: LLMService?.self) { group in
                group.addTask {
                    if let dir = prefetchedDirectory {
                        // Files already on disk — load directly, no download needed.
                        return try await LLMService.makeFromDirectory(dir)
                    } else {
                        return try await LLMService.make(progressHandler: progressHandler)
                    }
                }
                // Watchdog: throw URLError.timedOut if progress hasn't advanced for 90 seconds.
                group.addTask { [weak self] in
                    var lastSeen: Double = -1
                    var stalledSeconds: TimeInterval = 0
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(15))
                        guard !Task.isCancelled else { return nil }
                        let weakSelf = self
                        let current: Double = await MainActor.run { weakSelf?.llmProgress ?? 0 }
                        if current > lastSeen {
                            lastSeen = current
                            stalledSeconds = 0
                        } else {
                            stalledSeconds += 15
                            if stalledSeconds >= 90 { throw URLError(.timedOut) }
                        }
                    }
                    return nil
                }
                for try await result in group {
                    if let service = result { return service }
                }
                throw URLError(.timedOut)
            }
            animTask.cancel()
            llmService = service
            mlxWasInitializedThisSession = true
            llmProgress = 1.0
            isLLMReady = true
            UserDefaults.standard.set(true, forKey: kLLMReadyKey)
        } catch {
            downloadError = downloadErrorMessage(error, for: "Blog Generator")
        }
        #endif
    }

    func loadedLLMService() async throws -> LLMService {
        try await loadLLMService()
    }

    func prepareForLLMGeneration(releaseLLM: Bool = false) async {
        await cancelWhisperWarmTask()
        if let whisperKit {
            await whisperKit.unloadModels()
        }
        whisperKit = nil
        if releaseLLM {
            releaseLLMService()
        }
        if mlxWasInitializedThisSession {
            MLX.Memory.clearCache()
        }
    }

    private func cancelWhisperWarmTask() async {
        guard let task = whisperWarmTask else { return }
        task.cancel()
        whisperWarmTask = nil
        await task.value
    }

    func prepareForLLMGenerationBarrier(releaseLLM: Bool = false) async {
        await prepareForLLMGeneration(releaseLLM: releaseLLM)
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(750))
        if mlxWasInitializedThisSession {
            MLX.Memory.clearCache()
        }
        await Task.yield()
    }

    func releaseLLMService() {
        llmLoadTask?.cancel()
        llmLoadTask = nil
        llmService = nil
        if mlxWasInitializedThisSession {
            MLX.Memory.clearCache()
        }
    }

    private func loadLLMService(progressHandler: (@Sendable (Progress) -> Void)? = nil) async throws -> LLMService {
        #if !targetEnvironment(simulator)
        if let llmService {
            return llmService
        }

        if let llmLoadTask {
            return try await llmLoadTask.value
        }

        let task = Task { [isLLMReady] in
            // When the model is already on disk, load from the local cache directory
            // without any network calls. HubDownloader.download always hits the HF API
            // to resolve "main" → commit hash (a network request), which blocks for up
            // to timeoutIntervalForRequest before falling back to the local cache.
            if isLLMReady, let localDir = LLMService.localModelDirectory() {
                return try await LLMService.makeFromDirectory(localDir)
            }
            return try await LLMService.make(progressHandler: progressHandler)
        }
        llmLoadTask = task

        do {
            let service = try await task.value
            llmService = service
            mlxWasInitializedThisSession = true
            llmLoadTask = nil
            return service
        } catch {
            llmLoadTask = nil
            throw error
        }
        #else
        throw URLError(.unsupportedURL)
        #endif
    }

    func resetDownloads() {
        UserDefaults.standard.removeObject(forKey: kWhisperReadyKey)
        UserDefaults.standard.removeObject(forKey: kLLMReadyKey)
        isWhisperReady = false
        isLLMReady = false
        whisperProgress = 0
        llmProgress = 0
        downloadError = nil
        whisperKit = nil
        releaseLLMService()

        // Delete cached model files so stale/wrong-ID models don't block re-download
        let fm = FileManager.default
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let hfDir = docs.appendingPathComponent("huggingface")
            try? fm.removeItem(at: hfDir)
        }
    }
}
