import Foundation
import Observation
import CoreML
import WhisperKit
import MLX
import MLXLLM
import MLXLMCommon

let kLLMModelID = "mlx-community/gemma-4-e2b-it-4bit"
let kWhisperModelID = "openai_whisper-medium"

private let kWhisperReadyKey = "whisperModelReady_v4"
private let kLLMReadyKey = "llmModelReady_v1"

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

    // Retained so BlogView and InstagramView share one loaded instance — loading it twice OOMs.
    @ObservationIgnored var llmService: LLMService?
    @ObservationIgnored private var llmLoadTask: Task<LLMService, Error>?

    var allModelsReady: Bool { isWhisperReady && isLLMReady }
    var hasLoadedLLMService: Bool { llmService != nil }

    init() {
        isWhisperReady = UserDefaults.standard.bool(forKey: kWhisperReadyKey)
        isLLMReady = UserDefaults.standard.bool(forKey: kLLMReadyKey)
        if isWhisperReady { whisperProgress = 1.0 }
        if isLLMReady { llmProgress = 1.0 }
    }

    func downloadAll() async {
        guard !allModelsReady else { return }
        isDownloading = true
        downloadError = nil

        // Sequential — loading both models concurrently peaks at ~1.5 GB and kills the process.
        if !isWhisperReady { await downloadWhisper() }
        if downloadError == nil, !isLLMReady { await downloadLLM() }

        isDownloading = false
    }

    private func downloadWhisper() async {
        do {
            whisperProgress = 0.05
            // WhisperKit downloads the CoreML model from argmaxinc/whisperkit-coreml on first init.
            // Use cpuAndGPU to avoid ANE failures on devices with unknown/mismatched ANE hardware.
            let config = WhisperKitConfig(
                model: kWhisperModelID,
                computeOptions: ModelComputeOptions(
                    audioEncoderCompute:  .cpuAndGPU,
                    textDecoderCompute: .cpuAndGPU
                )
            )
            let kit = try await WhisperKit(config)
            whisperKit = kit
            whisperProgress = 1.0
            isWhisperReady = true
            UserDefaults.standard.set(true, forKey: kWhisperReadyKey)
        } catch {
            downloadError = "WhisperKit: \(error.localizedDescription)"
        }
    }

    private func downloadLLM() async {
        do {
            _ = try await LLMService.make { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.llmProgress = progress.fractionCompleted
                }
            }
            releaseLLMService()
            llmProgress = 1.0
            isLLMReady = true
            UserDefaults.standard.set(true, forKey: kLLMReadyKey)
        } catch {
            downloadError = "LLM: \(error.localizedDescription)"
        }
    }

    func loadedLLMService() async throws -> LLMService {
        try await loadLLMService()
    }

    func prepareForLLMGeneration(releaseLLM: Bool = false) {
        whisperKit = nil
        if releaseLLM {
            releaseLLMService()
        }
        MLX.Memory.clearCache()
    }

    func prepareForLLMGenerationBarrier(releaseLLM: Bool = false) async {
        prepareForLLMGeneration(releaseLLM: releaseLLM)
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(750))
        MLX.Memory.clearCache()
        await Task.yield()
    }

    func releaseLLMService() {
        llmLoadTask?.cancel()
        llmLoadTask = nil
        llmService = nil
        MLX.Memory.clearCache()
    }

    private func loadLLMService(progressHandler: (@Sendable (Progress) -> Void)? = nil) async throws -> LLMService {
        if let llmService {
            return llmService
        }

        if let llmLoadTask {
            return try await llmLoadTask.value
        }

        let task = Task {
            try await LLMService.make(progressHandler: progressHandler)
        }
        llmLoadTask = task

        do {
            let service = try await task.value
            llmService = service
            llmLoadTask = nil
            return service
        } catch {
            llmLoadTask = nil
            throw error
        }
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
