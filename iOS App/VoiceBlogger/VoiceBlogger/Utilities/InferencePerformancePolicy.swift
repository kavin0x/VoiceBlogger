import Foundation
import CoreML
import MLXLMCommon
import WhisperKit

/// Centralized, device-tier-aware tuning for on-device Whisper and MLX inference.
enum InferencePerformancePolicy {
    // MARK: - Live recording chunks (16 kHz samples)

    /// Samples advanced per live chunk — smaller windows surface text sooner on fast devices.
    nonisolated static var liveChunkAdvanceSamples: Int {
        switch DeviceRAMTier.current {
        case .ample: return 8 * 16_000
        case .standard: return 12 * 16_000
        case .constrained: return 20 * 16_000
        }
    }

    nonisolated static let liveChunkOverlapSamples = Int(2.5 * 16_000)

    nonisolated static var liveChunkWindowSamples: Int {
        liveChunkAdvanceSamples + liveChunkOverlapSamples
    }

    /// Recording length (seconds) covered by a single live chunk on this device.
    nonisolated static var liveChunkAdvanceSeconds: TimeInterval {
        TimeInterval(liveChunkAdvanceSamples) / 16_000
    }

    // MARK: - Transcription refinement

    /// Skip the authoritative full-file pass when the live preview already covered the recording.
    nonisolated static func shouldSkipFullFileRefinement(
        recordingDuration: TimeInterval,
        previewText: String,
        hadLivePreview: Bool
    ) -> Bool {
        guard hadLivePreview else { return false }
        let trimmed = previewText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else { return false }
        let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
        guard wordCount >= 4 else { return false }
        // One live chunk (+ tail) already spans the full recording.
        return recordingDuration <= liveChunkAdvanceSeconds + 3
    }

    // MARK: - Whisper

    nonisolated static func whisperComputeOptions() -> ModelComputeOptions {
        guard hasAvailableMemory(requiredMB: 600) else {
            return ModelComputeOptions(
                audioEncoderCompute: .cpuOnly,
                textDecoderCompute: .cpuOnly
            )
        }

        switch DeviceRAMTier.current {
        case .ample:
            return ModelComputeOptions(
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine
            )
        case .standard, .constrained:
            // Encoder on ANE is the biggest win; CPU decoder frees ANE sooner for MLX handoff.
            return ModelComputeOptions(
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuOnly
            )
        }
    }

    nonisolated static func whisperConcurrentWorkers(livePreview: Bool) -> Int {
        if livePreview { return 1 }
        switch DeviceRAMTier.current {
        case .ample: return 2
        case .standard, .constrained: return 1
        }
    }

    nonisolated static func whisperTemperatureFallbackCount(livePreview: Bool) -> Int {
        livePreview ? 2 : 3
    }

    /// VAD chunking helps long recordings stay within memory and can reduce wall time.
    nonisolated static func whisperChunkingStrategy(audioDuration: TimeInterval) -> ChunkingStrategy? {
        audioDuration > 45 ? .vad : .none
    }

    // MARK: - LLM

    nonisolated static var parallelChunkSummaryWidth: Int {
        switch DeviceRAMTier.current {
        case .ample: return 3
        case .standard: return 2
        case .constrained: return 1
        }
    }

    nonisolated static func llmGenerateParameters(
        maxTokens: Int,
        temperature: Float
    ) -> GenerateParameters {
        var params = GenerateParameters()
        params.maxTokens = maxTokens
        params.temperature = temperature
        params.topP = 0.92
        params.repetitionPenalty = 1.12
        params.repetitionContextSize = 128
        params.frequencyPenalty = 0.08
        params.frequencyContextSize = 160

        switch DeviceRAMTier.current {
        case .constrained:
            params.kvBits = 8
            params.kvGroupSize = 64
        case .standard:
            params.kvBits = 8
            params.kvGroupSize = 64
        case .ample:
            // Larger prefill chunks improve prompt throughput on long transcripts.
            params.prefillStepSize = 1024
        }
        return params
    }
}
