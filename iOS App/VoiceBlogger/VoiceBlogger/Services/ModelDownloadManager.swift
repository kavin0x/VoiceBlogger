import Foundation
import Observation
import WhisperKit
import MLXLLM
import MLXLMCommon

let kLLMModelID = "mlx-community/gemma-4-e2b-it-4bit"
let kWhisperModelID = "openai_whisper-large-v3-v20240930_626MB"

private let kWhisperReadyKey = "whisperModelReady_v1"
private let kLLMReadyKey = "llmModelReady_v1"

@Observable
final class ModelDownloadManager {
    var whisperProgress: Double = 0
    var llmProgress: Double = 0
    var isWhisperReady: Bool
    var isLLMReady: Bool
    var downloadError: String?
    var isDownloading = false

    var allModelsReady: Bool { isWhisperReady && isLLMReady }

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

        await withTaskGroup(of: Void.self) { group in
            if !isWhisperReady {
                group.addTask { await self.downloadWhisper() }
            }
            if !isLLMReady {
                group.addTask { await self.downloadLLM() }
            }
        }
        isDownloading = false
    }

    private func downloadWhisper() async {
        do {
            whisperProgress = 0.05
            // WhisperKit downloads the CoreML model from argmaxinc/whisperkit-coreml on first init
            let _ = try await WhisperKit(model: kWhisperModelID)
            whisperProgress = 1.0
            isWhisperReady = true
            UserDefaults.standard.set(true, forKey: kWhisperReadyKey)
        } catch {
            downloadError = "WhisperKit: \(error.localizedDescription)"
        }
    }

    private func downloadLLM() async {
        do {
            let _ = try await LLMModelFactory.shared.loadContainer(
                from: HubDownloader(),
                using: HuggingFaceTokenizerLoader(),
                configuration: ModelConfiguration(id: kLLMModelID),
                progressHandler: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.llmProgress = progress.fractionCompleted
                    }
                }
            )
            llmProgress = 1.0
            isLLMReady = true
            UserDefaults.standard.set(true, forKey: kLLMReadyKey)
        } catch {
            downloadError = "LLM: \(error.localizedDescription)"
        }
    }

    func resetDownloads() {
        UserDefaults.standard.removeObject(forKey: kWhisperReadyKey)
        UserDefaults.standard.removeObject(forKey: kLLMReadyKey)
        isWhisperReady = false
        isLLMReady = false
        whisperProgress = 0
        llmProgress = 0
    }
}
