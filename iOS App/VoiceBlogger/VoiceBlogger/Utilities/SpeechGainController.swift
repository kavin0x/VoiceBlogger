import AVFoundation
import Foundation

/// Smooths gain across buffers so quiet speech is boosted without pumping between chunks.
final class SpeechGainController: @unchecked Sendable {
    private let lock = NSLock()
    private var envelope: Float = 1.0

    nonisolated init() {}

    nonisolated func reset() {
        lock.lock()
        envelope = 1.0
        lock.unlock()
    }

    /// Returns a gain multiplier for the given peak amplitude in [-1, 1].
    nonisolated func gain(forPeak peak: Float) -> Float {
        lock.lock()
        defer { lock.unlock() }

        guard peak >= Self.minimumPeak else { return envelope }

        let desired = min(Self.targetPeak / peak, Self.maxGain)
        if desired > envelope {
            envelope = 0.35 * envelope + 0.65 * desired
        } else {
            envelope = 0.9 * envelope + 0.1 * desired
        }
        return min(envelope, Self.maxGain)
    }

    nonisolated static func applyGain(_ gain: Float, to samples: inout [Float]) {
        guard gain > 1.02 else { return }
        for index in samples.indices {
            samples[index] = max(-1, min(1, samples[index] * gain))
        }
    }

    nonisolated static func applyGain(_ gain: Float, to buffer: AVAudioPCMBuffer) {
        guard gain > 1.02,
              buffer.format.commonFormat == .pcmFormatFloat32,
              let channelData = buffer.floatChannelData?[0] else {
            return
        }

        let count = Int(buffer.frameLength)
        for index in 0..<count {
            channelData[index] = max(-1, min(1, channelData[index] * gain))
        }
    }

    private nonisolated static let targetPeak: Float = 0.55
    private nonisolated static let maxGain: Float = 10.0
    private nonisolated static let minimumPeak: Float = 0.006
}
