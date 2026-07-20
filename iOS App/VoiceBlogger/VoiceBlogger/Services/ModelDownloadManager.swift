import Foundation
import Observation
import UIKit
import CoreML
import WhisperKit
import MLX
import MLXLLM
import MLXLMCommon

private let kWhisperReadyKey = "whisperModelReady_v4"
private let kLLMReadyKey = "llmModelReady_v4"
private let kModelDownloadStartedKey = "modelDownloadStarted_v1"
private let kWhisperFingerprintKey = "whisperModelFingerprint_v1"
private let kLLMFingerprintKey = "llmModelFingerprint_v1"
private let kInstalledWhisperModelIDKey = "installedWhisperModelID_v1"
private let kInstalledLLMModelIDKey = "installedLLMModelID_v1"
private let kDeclinedWhisperUpdateIDKey = "declinedWhisperModelUpdateID_v1"
private let kDeclinedLLMUpdateIDKey = "declinedLLMModelUpdateID_v1"

enum ModelUpdateDomain: String, Equatable, Sendable {
    case speechRecognition
    case writingAssistant

    var displayName: String {
        switch self {
        case .speechRecognition: return String(localized: "Speech Recognition")
        case .writingAssistant: return String(localized: "Writing Assistant")
        }
    }
}

struct PendingModelUpdate: Equatable, Identifiable {
    let domain: ModelUpdateDomain
    let installedID: String
    let availableID: String

    var id: String { domain.rawValue }

    var alertTitle: String {
        String(localized: "New \(domain.displayName) Model")
    }

    var alertMessage: String {
        String(
            localized: "A newer \(domain.displayName.lowercased()) model is available. Would you like to download it? Your current model keeps working until the update finishes."
        )
    }
}

@MainActor
@Observable
final class ModelDownloadManager {
    var whisperProgress: Double = 0 {
        didSet { updateDownloadLiveActivityIfNeeded() }
    }
    var llmProgress: Double = 0 {
        didSet { updateDownloadLiveActivityIfNeeded() }
    }
    var isWhisperReady: Bool
    var isLLMReady: Bool
    var downloadError: String?
    var isDownloading = false
    /// Optional single-domain model upgrade offered after an app update changes a model ID.
    var pendingModelUpdate: PendingModelUpdate?
    /// Non-nil while a domain-scoped catalog update is downloading (drives banner + Live Activity).
    var activeUpdateDomain: ModelUpdateDomain?

    // Retained after download so TranscriptionService can reuse it without reloading from disk.
    @ObservationIgnored var whisperKit: WhisperKit?
    @ObservationIgnored var whisperWarmTask: Task<Void, Never>?
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var downloadRunID = UUID()
    @ObservationIgnored private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private let liveActivityCoordinator = LiveActivityCoordinator()

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
    var hasLoadedWhisperKit: Bool { whisperKit != nil }

    // Cache disk-scan results so repeated calls to validatePersistedModelReadiness
    // (warmWhisper, continuePendingDownloadIfNeeded, etc.) don't hammer the filesystem.
    // Invalidated only by resetDownloads() or when a download completes.
    @ObservationIgnored private var validationCacheValid = false

    init() {
        isWhisperReady = UserDefaults.standard.bool(forKey: kWhisperReadyKey)
        isLLMReady = UserDefaults.standard.bool(forKey: kLLMReadyKey)
        validatePersistedModelReadiness()
    }

    func validatePersistedModelReadiness() {
        // Only scan disk once per session unless something changes.
        if validationCacheValid && allModelsReady { return }

        let whisperDir = Self.localWhisperModelDirectory()
        let whisperIntegrity = whisperDir.map {
            ModelIntegrityChecker.verify(directory: $0, storedKey: kWhisperFingerprintKey)
        } ?? false
        let whisperWasReady = isWhisperReady
            || UserDefaults.standard.bool(forKey: kWhisperReadyKey)
            || Self.legacyReadyFlag(for: .whisper)

        if ModelInstallRetentionPolicy.shouldKeepInstalledModel(
            directoryExists: whisperDir != nil,
            integrityMatches: whisperIntegrity,
            wasMarkedReady: whisperWasReady
        ), let whisperDir {
            // Keep installed models across app updates. Fingerprint may be missing
            // (legacy) or drift (CoreML rewrite) without requiring a reinstall.
            if !whisperIntegrity, let fp = ModelIntegrityChecker.fingerprint(of: whisperDir) {
                ModelIntegrityChecker.store(fingerprint: fp, forKey: kWhisperFingerprintKey)
            }
            if !isWhisperReady {
                isWhisperReady = true
                UserDefaults.standard.set(true, forKey: kWhisperReadyKey)
            }
            if UserDefaults.standard.string(forKey: kInstalledWhisperModelIDKey) == nil {
                UserDefaults.standard.set(whisperDir.lastPathComponent, forKey: kInstalledWhisperModelIDKey)
            }
            whisperProgress = 1.0
        } else if whisperDir != nil {
            // Partial cache without a prior completion — resume in place; never delete.
            isWhisperReady = false
            whisperProgress = 0
            UserDefaults.standard.removeObject(forKey: kWhisperReadyKey)
            UserDefaults.standard.set(true, forKey: kModelDownloadStartedKey)
        } else if isWhisperReady || whisperWasReady {
            isWhisperReady = false
            whisperProgress = 0
            UserDefaults.standard.removeObject(forKey: kWhisperReadyKey)
            ModelIntegrityChecker.invalidate(forKey: kWhisperFingerprintKey)
            UserDefaults.standard.set(true, forKey: kModelDownloadStartedKey)
        }

        let llmDir = LLMService.localModelDirectory()
        let llmIntegrity = llmDir.map {
            ModelIntegrityChecker.verify(directory: $0, storedKey: kLLMFingerprintKey)
        } ?? false
        let llmWasReady = isLLMReady
            || UserDefaults.standard.bool(forKey: kLLMReadyKey)
            || Self.legacyReadyFlag(for: .llm)

        if ModelInstallRetentionPolicy.shouldKeepInstalledModel(
            directoryExists: llmDir != nil,
            integrityMatches: llmIntegrity,
            wasMarkedReady: llmWasReady
        ), let llmDir {
            if !llmIntegrity, let fp = ModelIntegrityChecker.fingerprint(of: llmDir) {
                ModelIntegrityChecker.store(fingerprint: fp, forKey: kLLMFingerprintKey)
            }
            if !isLLMReady {
                isLLMReady = true
                UserDefaults.standard.set(true, forKey: kLLMReadyKey)
            }
            if UserDefaults.standard.string(forKey: kInstalledLLMModelIDKey) == nil {
                UserDefaults.standard.set(ModelIDs.llm, forKey: kInstalledLLMModelIDKey)
            }
            llmProgress = 1.0
        } else if llmDir != nil {
            isLLMReady = false
            llmProgress = 0
            UserDefaults.standard.removeObject(forKey: kLLMReadyKey)
            UserDefaults.standard.set(true, forKey: kModelDownloadStartedKey)
        } else if isLLMReady || llmWasReady {
            isLLMReady = false
            llmProgress = 0
            UserDefaults.standard.removeObject(forKey: kLLMReadyKey)
            ModelIntegrityChecker.invalidate(forKey: kLLMFingerprintKey)
            UserDefaults.standard.set(true, forKey: kModelDownloadStartedKey)
        }

        if allModelsReady {
            UserDefaults.standard.removeObject(forKey: kModelDownloadStartedKey)
            validationCacheValid = true
        }

        evaluatePendingModelUpdates()
    }

    /// Detects when the app's configured model ID changed for a single domain while an older
    /// installed model still works. Offers an optional domain-scoped download — never both.
    func evaluatePendingModelUpdates() {
        guard !isDownloading, pendingModelUpdate == nil else { return }

        if isWhisperReady,
           let installed = installedWhisperModelID(),
           installed != ModelIDs.whisper,
           UserDefaults.standard.string(forKey: kDeclinedWhisperUpdateIDKey) != ModelIDs.whisper {
            pendingModelUpdate = PendingModelUpdate(
                domain: .speechRecognition,
                installedID: installed,
                availableID: ModelIDs.whisper
            )
            return
        }

        if isLLMReady,
           let installed = UserDefaults.standard.string(forKey: kInstalledLLMModelIDKey),
           installed != ModelIDs.llm,
           UserDefaults.standard.string(forKey: kDeclinedLLMUpdateIDKey) != ModelIDs.llm {
            pendingModelUpdate = PendingModelUpdate(
                domain: .writingAssistant,
                installedID: installed,
                availableID: ModelIDs.llm
            )
        }
    }

    func acceptPendingModelUpdate() {
        guard let update = pendingModelUpdate else { return }
        pendingModelUpdate = nil
        activeUpdateDomain = update.domain
        Task { await downloadDomainUpdate(update.domain) }
    }

    func declinePendingModelUpdate() {
        guard let update = pendingModelUpdate else { return }
        switch update.domain {
        case .speechRecognition:
            UserDefaults.standard.set(update.availableID, forKey: kDeclinedWhisperUpdateIDKey)
        case .writingAssistant:
            UserDefaults.standard.set(update.availableID, forKey: kDeclinedLLMUpdateIDKey)
        }
        pendingModelUpdate = nil
        evaluatePendingModelUpdates()
    }

    /// Downloads only the requested domain's new model, leaving the other domain untouched.
    func downloadDomainUpdate(_ domain: ModelUpdateDomain) async {
        pendingModelUpdate = nil
        activeUpdateDomain = domain
        UserDefaults.standard.set(true, forKey: kModelDownloadStartedKey)

        if let downloadTask {
            await downloadTask.value
            return
        }

        let runID = UUID()
        downloadRunID = runID
        let task = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.performDomainUpdate(domain, runID: runID)
        }
        downloadTask = task
        isDownloading = true
        downloadError = nil
        beginBackgroundContinuation()
        liveActivityCoordinator.startDownload(
            progress: overallDownloadProgress,
            detail: currentDownloadDetail,
            title: downloadLiveActivityTitle
        )
        await task.value
    }

    private func performDomainUpdate(_ domain: ModelUpdateDomain, runID: UUID) async {
        defer {
            if downloadRunID == runID {
                let succeeded = downloadError == nil
                isDownloading = false
                downloadTask = nil
                activeUpdateDomain = nil
                endBackgroundContinuation()
                liveActivityCoordinator.endDownload(isComplete: succeeded)
                if allModelsReady {
                    UserDefaults.standard.removeObject(forKey: kModelDownloadStartedKey)
                }
                evaluatePendingModelUpdates()
            }
        }

        guard downloadRunID == runID, !Task.isCancelled else { return }
        downloadError = nil
        activeUpdateDomain = domain

        switch domain {
        case .speechRecognition:
            // Keep the old Speech model usable for recording while the new one downloads.
            whisperWarmTask?.cancel()
            whisperWarmTask = nil
            if let kit = whisperKit {
                whisperKit = nil
                await kit.unloadModels()
            }
            whisperProgress = 0
            await downloadWhisper(runID: runID, forceNewCatalogID: true)
            if downloadError == nil, isWhisperReady {
                removeStaleWhisperModelDirectories(keeping: ModelIDs.whisper)
                UserDefaults.standard.set(ModelIDs.whisper, forKey: kInstalledWhisperModelIDKey)
                UserDefaults.standard.removeObject(forKey: kDeclinedWhisperUpdateIDKey)
                await warmWhisper()
            }
        case .writingAssistant:
            await prepareForLLMGenerationBarrier(releaseLLM: true)
            llmProgress = 0
            isLLMReady = false
            UserDefaults.standard.removeObject(forKey: kLLMReadyKey)
            ModelIntegrityChecker.invalidate(forKey: kLLMFingerprintKey)
            await downloadLLM(prefetchedDirectory: nil, runID: runID)
            if downloadError == nil, isLLMReady {
                UserDefaults.standard.set(ModelIDs.llm, forKey: kInstalledLLMModelIDKey)
                UserDefaults.standard.removeObject(forKey: kDeclinedLLMUpdateIDKey)
            }
        }
    }

    private func installedWhisperModelID() -> String? {
        if let stored = UserDefaults.standard.string(forKey: kInstalledWhisperModelIDKey), !stored.isEmpty {
            return stored
        }
        return Self.localWhisperModelDirectory()?.lastPathComponent
    }

    private enum LegacyReadyModel {
        case whisper
        case llm
    }

    /// Older builds used different ready-key suffixes; treat any of them as evidence
    /// the user already completed installation so an app update does not reinstall.
    private static func legacyReadyFlag(for model: LegacyReadyModel) -> Bool {
        let keys: [String]
        switch model {
        case .whisper:
            keys = [
                "whisperModelReady_v3",
                "whisperModelReady_v2",
                "whisperModelReady_v1",
                "whisperModelReady"
            ]
        case .llm:
            keys = [
                "llmModelReady_v3",
                "llmModelReady_v2",
                "llmModelReady_v1",
                "llmModelReady"
            ]
        }
        return keys.contains { UserDefaults.standard.bool(forKey: $0) }
    }

    // Returns the local WhisperKit model directory if it exists and contains at least one file.
    // Prefer the canonical path for the configured model ID only when it matches the stored
    // integrity fingerprint (or is already recorded as the installed catalog ID). Otherwise fall
    // back to any sibling so an older model remains usable while an optional update downloads.
    private static func localWhisperModelDirectory() -> URL? {
        if let canonical = canonicalWhisperModelDirectory() {
            let matchesFingerprint = ModelIntegrityChecker.verify(
                directory: canonical,
                storedKey: kWhisperFingerprintKey
            )
            let matchesInstalledID = UserDefaults.standard.string(forKey: kInstalledWhisperModelIDKey) == ModelIDs.whisper
            if matchesFingerprint || matchesInstalledID {
                return canonical
            }
        }

        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let whisperCacheDir = docs.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")

        guard let entries = try? fm.contentsOfDirectory(
            at: whisperCacheDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for entry in entries where entry.lastPathComponent != ModelIDs.whisper {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDir && directoryContainsFiles(entry) { return entry }
        }
        return nil
    }

    private static func canonicalWhisperModelDirectory() -> URL? {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let canonical = docs
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
            .appendingPathComponent(ModelIDs.whisper)
        return directoryContainsFiles(canonical) ? canonical : nil
    }

    private func removeStaleWhisperModelDirectories(keeping keepID: String) {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let whisperCacheDir = docs.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
        guard let entries = try? fm.contentsOfDirectory(
            at: whisperCacheDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for entry in entries where entry.lastPathComponent != keepID {
            try? fm.removeItem(at: entry)
        }
    }

    private static func directoryContainsFiles(_ directory: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return false }
        for case let url as URL in enumerator {
            let vals = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            if vals?.isRegularFile == true || vals?.isSymbolicLink == true { return true }
        }
        return false
    }

    private static func whisperModelDirectoryIsUsable() -> Bool {
        localWhisperModelDirectory() != nil
    }

    func warmWhisper() async {
        guard isWhisperReady, whisperKit == nil, whisperWarmTask == nil else { return }

        releaseLLMService()
        let localDir = Self.localWhisperModelDirectory()
        let task = Task { [weak self] in
            guard let self else { return }
            let config = WhisperKitConfig(
                model: localDir == nil ? ModelIDs.whisper : nil,
                modelFolder: localDir?.path,
                computeOptions: TranscriptionService.whisperComputeOptions()
            )
            guard !Task.isCancelled else { return }
            let kit: WhisperKit
            do {
                kit = try await WhisperKit(config)
            } catch {
                let integrityMatches = localDir.map {
                    ModelIntegrityChecker.verify(directory: $0, storedKey: kWhisperFingerprintKey)
                } ?? false
                if ModelLoadFailurePolicy.shouldInvalidate(error, integrityMatches: integrityMatches) {
                    self.markWhisperLoadFailure(error)
                }
                return
            }
            guard !Task.isCancelled else { return }
            do {
                try await kit.loadModels()
            } catch {
                await kit.unloadModels()
                let integrityMatches = localDir.map {
                    ModelIntegrityChecker.verify(directory: $0, storedKey: kWhisperFingerprintKey)
                } ?? false
                if ModelLoadFailurePolicy.shouldInvalidate(error, integrityMatches: integrityMatches) {
                    self.markWhisperLoadFailure(error)
                }
                return
            }
            guard !Task.isCancelled else {
                await kit.unloadModels()
                return
            }
            await MainActor.run { [weak self] in
                guard let self, self.whisperKit == nil else { return }
                self.whisperKit = kit
                self.whisperWarmTask = nil
                // Store fingerprint here, after loadModels() completes, so any CoreML
                // compilation artifacts written during loading are included in the baseline.
                if let dir = Self.localWhisperModelDirectory(),
                   let fp = ModelIntegrityChecker.fingerprint(of: dir) {
                    ModelIntegrityChecker.store(fingerprint: fp, forKey: kWhisperFingerprintKey)
                }
            }
        }
        whisperWarmTask = task
        await task.value
        whisperWarmTask = nil
    }

    /// Waits for any in-flight warm task, then warms if whisperKit is still nil.
    /// Call this just before transcription begins so the hot WhisperKit instance
    /// is ready for TranscriptionService.make(reusing:) without a cold reload.
    func ensureWhisperWarm() async throws {
        if let task = whisperWarmTask {
            await task.value
        }
        if whisperKit == nil {
            await warmWhisper()
        }
        guard whisperKit != nil else {
            throw ModelValidationError.whisperLoadFailed
        }
    }

    private func markWhisperLoadFailure(_ error: Error) {
        whisperKit = nil
        isWhisperReady = false
        whisperProgress = 0
        validationCacheValid = false
        UserDefaults.standard.removeObject(forKey: kWhisperReadyKey)
        ModelIntegrityChecker.invalidate(forKey: kWhisperFingerprintKey)
        UserDefaults.standard.set(true, forKey: kModelDownloadStartedKey)
        downloadError = "Speech Recognition could not load: \(error.localizedDescription)"
    }

    /// Pre-warm the LLM while the user reviews or edits a transcript.
    func warmLLMIfNeeded() {
        guard isLLMReady, llmService == nil, llmLoadTask == nil else { return }
        Task { _ = try? await loadLLMService() }
    }

    var hasPendingDownload: Bool {
        UserDefaults.standard.bool(forKey: kModelDownloadStartedKey) && !allModelsReady
    }

    func continuePendingDownloadIfNeeded() {
        validatePersistedModelReadiness()
        guard hasPendingDownload else { return }
        startDownloadTaskIfNeeded()
    }

    func downloadAll() async {
        validatePersistedModelReadiness()
        guard !allModelsReady else { return }
        UserDefaults.standard.set(true, forKey: kModelDownloadStartedKey)
        let task = startDownloadTaskIfNeeded()
        await task.value
    }

    @discardableResult
    private func startDownloadTaskIfNeeded() -> Task<Void, Never> {
        if let downloadTask {
            return downloadTask
        }

        let runID = UUID()
        downloadRunID = runID
        let task = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.performDownloadAll(runID: runID)
        }
        downloadTask = task
        isDownloading = true
        downloadError = nil
        beginBackgroundContinuation()
        liveActivityCoordinator.startDownload(
            progress: overallDownloadProgress,
            detail: currentDownloadDetail,
            title: downloadLiveActivityTitle
        )
        return task
    }

    private func performDownloadAll(runID: UUID) async {
        defer {
            if downloadRunID == runID {
                isDownloading = false
                downloadTask = nil
                endBackgroundContinuation()
                liveActivityCoordinator.endDownload(isComplete: allModelsReady)
                if allModelsReady {
                    UserDefaults.standard.removeObject(forKey: kModelDownloadStartedKey)
                }
            }
        }

        guard !allModelsReady, downloadRunID == runID, !Task.isCancelled else { return }
        downloadError = nil

        if !isWhisperReady {
            // Prefetch LLM files to disk concurrently with the whisper download.
            // resolve() is pure network->disk: it holds zero RAM, so running it alongside
            // whisper is safe. Only the subsequent _load() step (loadContainer(from:directory))
            // pulls weights into memory, and that is deferred until after whisper unloads.
            let localLLMDirectory = LLMService.localModelDirectory()
            let prefetchTask = Task.detached(priority: .userInitiated) { [weak self] () -> URL? in
                // Prefer on-disk snapshots after app updates. Incomplete caches fail
                // local load and fall through to resumable network download.
                if let localDirectory = localLLMDirectory {
                    return localDirectory
                }
                return try? await resolve(
                    configuration: ModelConfiguration(id: ModelIDs.llm),
                    from: HubDownloader(),
                    useLatest: false,
                    progressHandler: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            guard let self, self.downloadRunID == runID, !self.isLLMReady else { return }
                            let real = max(0.05, min(progress.fractionCompleted, 0.95))
                            if real > self.llmProgress {
                                self.llmProgress = real
                            }
                        }
                    }
                ).modelDirectory
            }
            await downloadWhisper(runID: runID)

            guard downloadRunID == runID, !Task.isCancelled else {
                prefetchTask.cancel()
                return
            }

            if downloadError == nil {
                // Release whisper from RAM before loading the LLM; holding both
                // (~1.5 GB total) kills the process.
                await prepareForLLMGenerationBarrier()
                let prefetchedDir = await prefetchTask.value
                guard downloadRunID == runID, !Task.isCancelled else { return }
                await downloadLLM(prefetchedDirectory: prefetchedDir, runID: runID)
            } else {
                prefetchTask.cancel()
            }
        } else if !isLLMReady {
            let local = LLMService.localModelDirectory()
            await downloadLLM(prefetchedDirectory: local, runID: runID)
        }
    }

    private func beginBackgroundContinuation() {
        #if os(iOS)
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "Model Download") { [weak self] in
            Task { @MainActor [weak self] in
                self?.endBackgroundContinuation()
            }
        }
        #endif
    }

    /// Progress for the in-app top banner during a domain-scoped model update.
    var updateBannerProgress: Double {
        guard let domain = activeUpdateDomain else { return overallDownloadProgress }
        switch domain {
        case .speechRecognition: return min(max(whisperProgress, 0), 1)
        case .writingAssistant: return min(max(llmProgress, 0), 1)
        }
    }

    var updateBannerDetail: String {
        currentDownloadDetail
    }

    private var overallDownloadProgress: Double {
        if let domain = activeUpdateDomain {
            switch domain {
            case .speechRecognition: return min(max(whisperProgress, 0), 1)
            case .writingAssistant: return min(max(llmProgress, 0), 1)
            }
        }
        let whisper = isWhisperReady ? 1 : whisperProgress
        let llm = isLLMReady ? 1 : llmProgress
        return (whisper + llm) / 2
    }

    private var currentDownloadDetail: String {
        if let domain = activeUpdateDomain {
            switch domain {
            case .speechRecognition:
                return "Speech Recognition \(whisperProgress.formatted(.percent.precision(.fractionLength(0))))"
            case .writingAssistant:
                return "Writing Assistant \(llmProgress.formatted(.percent.precision(.fractionLength(0))))"
            }
        }
        if !isWhisperReady {
            return "Speech Recognition \(whisperProgress.formatted(.percent.precision(.fractionLength(0))))"
        }
        if !isLLMReady {
            return "Blog Generator \(llmProgress.formatted(.percent.precision(.fractionLength(0))))"
        }
        return "Finalizing setup"
    }

    private var downloadLiveActivityTitle: String {
        if let domain = activeUpdateDomain {
            return "Updating \(domain.displayName)"
        }
        return "Downloading Models"
    }

    private func updateDownloadLiveActivityIfNeeded() {
        guard isDownloading else { return }
        liveActivityCoordinator.updateDownload(
            progress: overallDownloadProgress,
            detail: currentDownloadDetail,
            title: downloadLiveActivityTitle
        )
    }

    private func endBackgroundContinuation() {
        #if os(iOS)
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
        #endif
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
        func isOutOfSpaceError(_ e: Error) -> Bool {
            let ns = e as NSError
            if ns.domain == NSCocoaErrorDomain && ns.code == CocoaError.fileWriteOutOfSpace.rawValue { return true }
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error { return isOutOfSpaceError(underlying) }
            return false
        }
        if isOutOfSpaceError(error) {
            return "Not enough free storage for model setup. Free space and tap Retry to continue."
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

    private func downloadWhisper(runID: UUID, forceNewCatalogID: Bool = false) async {
        do {
            guard downloadRunID == runID, !Task.isCancelled else { return }

            let existingDir = forceNewCatalogID
                ? Self.canonicalWhisperModelDirectory()
                : Self.localWhisperModelDirectory()
            let existingDownloadIsComplete = !forceNewCatalogID && (existingDir.map {
                ModelIntegrityChecker.verify(directory: $0, storedKey: kWhisperFingerprintKey)
            } ?? false)

            if !existingDownloadIsComplete,
               let existingDir,
               !forceNewCatalogID {
                if await validateLocalWhisperDirectory(existingDir, runID: runID) {
                    return
                }
                guard WhisperDownloadContinuation.shouldContinueAfterLocalValidation(
                    validationSucceeded: false,
                    runStillActive: downloadRunID == runID,
                    isCancelled: Task.isCancelled
                ) else {
                    return
                }
            }

            if forceNewCatalogID || !existingDownloadIsComplete {
                whisperProgress = 0.05
                // Download model files with load: false — files land on disk without
                // pulling CoreML weights into RAM. No progress callback is available here,
                // so animate smoothly to 0.45 while the ~800 MB transfer runs.
                let config = WhisperKitConfig(
                    model: ModelIDs.whisper,
                    computeOptions: TranscriptionService.whisperComputeOptions(),
                    load: false
                )
                let progressTask = Task { @MainActor [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1))
                        guard let self, self.downloadRunID == runID, !self.isWhisperReady || forceNewCatalogID, !Task.isCancelled else { return }
                        let next = min(self.whisperProgress + 0.002, 0.45)
                        if next > self.whisperProgress { self.whisperProgress = next }
                    }
                }
                defer { progressTask.cancel() }
                let kit = try await WhisperKit(config)
                guard downloadRunID == runID, !Task.isCancelled else {
                    await kit.unloadModels()
                    return
                }
                progressTask.cancel()
            }

            // Compile CoreML models now while the user is still on the download screen.
            // MLModel.load() writes a compiled .mlmodelc to the system cache on first run;
            // subsequent loads (warmWhisper, TranscriptionService.make) are fast reads.
            // prewarmModels() compiles without retaining the weights in RAM.
            guard downloadRunID == runID, !Task.isCancelled else { return }
            whisperProgress = 0.75
            let compileConfig = WhisperKitConfig(
                modelFolder: (Self.canonicalWhisperModelDirectory() ?? Self.localWhisperModelDirectory())?.path,
                computeOptions: TranscriptionService.whisperComputeOptions(),
                load: false
            )
            let compileKit = try await WhisperKit(compileConfig)
            guard downloadRunID == runID, !Task.isCancelled else {
                await compileKit.unloadModels()
                return
            }
            // Animate progress from 0.75 → 0.95 during the compilation phase so the bar
            // keeps moving while MLModel.load() compiles and caches the .mlmodelc.
            let compileProgressTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, self.downloadRunID == runID, !Task.isCancelled else { return }
                    let next = min(self.whisperProgress + 0.003, 0.95)
                    if next > self.whisperProgress { self.whisperProgress = next }
                }
            }
            defer { compileProgressTask.cancel() }
            try await compileKit.prewarmModels()
            compileProgressTask.cancel()
            await compileKit.unloadModels()

            guard downloadRunID == runID, !Task.isCancelled else { return }
            guard let completedDirectory = Self.canonicalWhisperModelDirectory() ?? Self.localWhisperModelDirectory(),
                  let fingerprint = ModelIntegrityChecker.fingerprint(of: completedDirectory) else {
                throw ModelValidationError.missingModelArtifacts
            }
            ModelIntegrityChecker.store(fingerprint: fingerprint, forKey: kWhisperFingerprintKey)
            whisperProgress = 1.0
            isWhisperReady = true
            UserDefaults.standard.set(true, forKey: kWhisperReadyKey)
            UserDefaults.standard.set(completedDirectory.lastPathComponent, forKey: kInstalledWhisperModelIDKey)
        } catch is CancellationError {
            return
        } catch {
            guard downloadRunID == runID else { return }
            downloadError = downloadErrorMessage(error, for: "Speech Recognition")
        }
    }

    private func validateLocalWhisperDirectory(_ directory: URL, runID: UUID) async -> Bool {
        do {
            let config = WhisperKitConfig(
                modelFolder: directory.path,
                computeOptions: TranscriptionService.whisperComputeOptions(),
                load: false
            )
            let kit = try await WhisperKit(config)
            guard downloadRunID == runID, !Task.isCancelled else {
                await kit.unloadModels()
                return false
            }
            try await kit.prewarmModels()
            await kit.unloadModels()
            guard downloadRunID == runID,
                  !Task.isCancelled,
                  let fingerprint = ModelIntegrityChecker.fingerprint(of: directory) else {
                return false
            }
            ModelIntegrityChecker.store(fingerprint: fingerprint, forKey: kWhisperFingerprintKey)
            whisperProgress = 1
            isWhisperReady = true
            UserDefaults.standard.set(true, forKey: kWhisperReadyKey)
            UserDefaults.standard.set(directory.lastPathComponent, forKey: kInstalledWhisperModelIDKey)
            return true
        } catch {
            return false
        }
    }

    private func downloadLLM(prefetchedDirectory: URL?, runID: UUID) async {
        // MLX's Metal device constructor calls device.name.UTF8String in C++, which returns
        // nullptr on the iOS 27 simulator, crashing the hardened libc++ string constructor.
        // MLX requires real GPU hardware and is not supported on simulator.
        #if targetEnvironment(simulator)
        guard downloadRunID == runID, !Task.isCancelled else { return }
        downloadError = "The AI Blog Generator requires a physical iPhone or iPad — the iOS Simulator is not supported."
        #else
        do {
            guard downloadRunID == runID, !Task.isCancelled else { return }

            // Before deserializing ~1 GB of weights, verify there is enough free RAM.
            // If Whisper just unloaded, give the OS one reclaim cycle.
            if !hasAvailableMemory(requiredMB: 600) {
                if mlxWasInitializedThisSession { MLX.Memory.clearCache() }
                try? await Task.sleep(for: .milliseconds(200))
                if !hasAvailableMemory(requiredMB: 500) {
                    throw LLMLoadError.insufficientMemory
                }
            }
            guard downloadRunID == runID, !Task.isCancelled else { return }

            // If prefetchedDirectory is set, files are already on disk — skip straight to loading.
            // Otherwise download + load in one pass (the original path, used when whisper was
            // already ready on launch so no prefetch task was started).
            let progressHandler: @Sendable (Foundation.Progress) -> Void = { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self, self.downloadRunID == runID else { return }
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
                    guard let self, self.downloadRunID == runID, !self.isLLMReady, !Task.isCancelled else { return }
                    let next = min(self.llmProgress + 0.004, 0.97)
                    if next > self.llmProgress {
                        self.llmProgress = next
                    }
                }
            }
            defer { animTask.cancel() }

            let service: LLMService
            if let dir = prefetchedDirectory {
                // Files already on disk — try weight deserialization first. If the snapshot
                // is incomplete (force-quit mid-download), fall through to a resumable
                // network load instead of looping forever on the partial cache.
                do {
                    service = try await LLMService.makeFromDirectory(dir)
                } catch {
                    guard !(error is CancellationError),
                          downloadRunID == runID,
                          !Task.isCancelled else { throw error }
                    service = try await withThrowingTaskGroup(of: LLMService?.self) { group in
                        group.addTask {
                            return try await LLMService.make(progressHandler: progressHandler)
                        }
                        group.addTask { [weak self] in
                            var lastSeen: Double = -1
                            var stalledSeconds: TimeInterval = 0
                            while !Task.isCancelled {
                                try? await Task.sleep(for: .seconds(15))
                                guard !Task.isCancelled else { return nil }
                                let weakSelf = self
                                let current: Double = await MainActor.run { weakSelf?.llmProgress ?? 0 }
                                if current >= 0.95 { return nil }
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
                }
            } else {
                service = try await withThrowingTaskGroup(of: LLMService?.self) { group in
                    group.addTask {
                        return try await LLMService.make(progressHandler: progressHandler)
                    }
                    // Watchdog: throw URLError.timedOut if download progress hasn't advanced
                    // for 90 seconds. Exits once progress reaches 0.95 (download complete,
                    // loading phase begun) so the silent weight-deserialization phase is not
                    // subject to a stall timeout.
                    group.addTask { [weak self] in
                        var lastSeen: Double = -1
                        var stalledSeconds: TimeInterval = 0
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(15))
                            guard !Task.isCancelled else { return nil }
                            let weakSelf = self
                            let current: Double = await MainActor.run { weakSelf?.llmProgress ?? 0 }
                            if current >= 0.95 { return nil }
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
            }
            guard downloadRunID == runID, !Task.isCancelled else { return }
            llmService = service
            mlxWasInitializedThisSession = true
            if let dir = LLMService.localModelDirectory(),
               let fp = ModelIntegrityChecker.fingerprint(of: dir) {
                ModelIntegrityChecker.store(fingerprint: fp, forKey: kLLMFingerprintKey)
            }
            llmProgress = 1.0
            isLLMReady = true
            UserDefaults.standard.set(true, forKey: kLLMReadyKey)
            UserDefaults.standard.set(ModelIDs.llm, forKey: kInstalledLLMModelIDKey)
        } catch is CancellationError {
            return
        } catch {
            guard downloadRunID == runID else { return }
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
        let hadWhisper = whisperKit != nil
        await prepareForLLMGeneration(releaseLLM: releaseLLM)
        await Task.yield()
        // Only sleep when we actually unloaded Whisper this call AND MLX is initialized.
        // If Whisper was already nil (pre-warm path) or MLX was never initialized, skip
        // the drain sleep to avoid 750 ms of dead time.
        if hadWhisper && mlxWasInitializedThisSession {
            try? await Task.sleep(for: .milliseconds(400))
            MLX.Memory.clearCache()
            await Task.yield()
        }
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

        // On RAM-constrained devices, give the OS time to reclaim pages after Whisper
        // unloads before we begin pulling 1 GB of LLM weights into memory.
        // If we still don't have enough headroom, throw a descriptive error rather
        // than attempting to load and triggering a jetsam OOM kill.
        if !hasAvailableMemory(requiredMB: 750) {
            if mlxWasInitializedThisSession {
                MLX.Memory.clearCache()
            }
            // Give the OS one more reclaim cycle before giving up.
            try? await Task.sleep(for: .milliseconds(200))
            if !hasAvailableMemory(requiredMB: 550) {
                throw LLMLoadError.insufficientMemory
            }
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
            let integrityMatches = LLMService.localModelDirectory().map {
                ModelIntegrityChecker.verify(directory: $0, storedKey: kLLMFingerprintKey)
            } ?? false
            if !(error is LLMLoadError),
               ModelLoadFailurePolicy.shouldInvalidate(error, integrityMatches: integrityMatches) {
                markLLMLoadFailure(error)
            }
            throw error
        }
        #else
        throw URLError(.unsupportedURL)
        #endif
    }

    private func markLLMLoadFailure(_ error: Error) {
        llmService = nil
        isLLMReady = false
        llmProgress = 0
        validationCacheValid = false
        UserDefaults.standard.removeObject(forKey: kLLMReadyKey)
        ModelIntegrityChecker.invalidate(forKey: kLLMFingerprintKey)
        UserDefaults.standard.set(true, forKey: kModelDownloadStartedKey)
        downloadError = "Writing Assistant could not load: \(error.localizedDescription)"
    }

    func resetDownloads() {
        validationCacheValid = false
        UserDefaults.standard.removeObject(forKey: kWhisperReadyKey)
        UserDefaults.standard.removeObject(forKey: kLLMReadyKey)
        UserDefaults.standard.removeObject(forKey: kModelDownloadStartedKey)
        UserDefaults.standard.removeObject(forKey: kInstalledWhisperModelIDKey)
        UserDefaults.standard.removeObject(forKey: kInstalledLLMModelIDKey)
        UserDefaults.standard.removeObject(forKey: kDeclinedWhisperUpdateIDKey)
        UserDefaults.standard.removeObject(forKey: kDeclinedLLMUpdateIDKey)
        ModelIntegrityChecker.invalidate(forKey: kWhisperFingerprintKey)
        ModelIntegrityChecker.invalidate(forKey: kLLMFingerprintKey)
        isWhisperReady = false
        isLLMReady = false
        pendingModelUpdate = nil
        whisperProgress = 0
        llmProgress = 0
        downloadError = nil
        activeUpdateDomain = nil
        // Invalidate in-flight callbacks before clearing state so stale downloads
        // cannot mark models ready after a reset.
        downloadRunID = UUID()
        downloadTask?.cancel()
        downloadTask = nil
        endBackgroundContinuation()
        liveActivityCoordinator.endDownload(isComplete: false)
        isDownloading = false
        whisperWarmTask?.cancel()
        whisperWarmTask = nil
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

enum LLMLoadError: LocalizedError {
    case insufficientMemory

    var errorDescription: String? {
        switch self {
        case .insufficientMemory:
            return "Not enough free memory to load the AI model. Close other apps, then try again."
        }
    }
}

enum ModelValidationError: LocalizedError {
    case missingModelArtifacts
    case whisperLoadFailed

    var errorDescription: String? {
        switch self {
        case .missingModelArtifacts:
            return "The model download did not finish writing all required files. Tap Retry to resume."
        case .whisperLoadFailed:
            return "The speech model could not load and needs to be repaired."
        }
    }
}

enum ModelLoadFailurePolicy {
    static func shouldInvalidate(_ error: Error, integrityMatches: Bool) -> Bool {
        guard !integrityMatches else { return false }
        if error is CancellationError { return false }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return false
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return shouldInvalidate(underlying, integrityMatches: integrityMatches)
        }
        return true
    }
}

enum ModelInstallRetentionPolicy {
    /// Keep installed model files across app updates. A missing or drifted fingerprint
    /// is not enough to discard a previously completed install; only a missing directory
    /// should force a fresh download. Partial caches (dir present, never marked ready,
    /// no matching fingerprint) stay on disk for resume without being marked ready.
    static func shouldKeepInstalledModel(
        directoryExists: Bool,
        integrityMatches: Bool,
        wasMarkedReady: Bool
    ) -> Bool {
        guard directoryExists else { return false }
        return integrityMatches || wasMarkedReady
    }
}

enum LocalModelTrustPolicy {
    /// Prefer local Hub snapshots whenever they exist. Incomplete snapshots fail local
    /// load and fall through to resumable network download — they must not trigger a
    /// delete/reinstall after an app update just because the fingerprint is missing.
    static func shouldPreferNetworkResume(hasLocalDirectory: Bool) -> Bool {
        !hasLocalDirectory
    }
}

enum WhisperDownloadContinuation {
    static func shouldContinueAfterLocalValidation(
        validationSucceeded: Bool,
        runStillActive: Bool,
        isCancelled: Bool
    ) -> Bool {
        !validationSucceeded && runStillActive && !isCancelled
    }
}
