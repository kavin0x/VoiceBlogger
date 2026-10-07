import AVFoundation
import Foundation

/// Capture settings for the file the user plays back.
/// Live transcription still downsamples to Whisper's 16 kHz rate in memory.
enum RecordingAudioSettings {
    static let archiveSampleRate: Double = 48_000
    static let whisperSampleRate: Double = 16_000
    /// AAC-LC mono at 192 kbps is transparent for speech and smaller than 16 kHz float.
    static let archiveBitRate = 192_000

    /// Keep the hardware rate when it is already wideband so the archive is not resampled.
    static func archiveSampleRate(matching hardwareSampleRate: Double) -> Double {
        hardwareSampleRate >= 44_100 ? hardwareSampleRate : archiveSampleRate
    }

    static func archiveFileSettings(sampleRate: Double = archiveSampleRate) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: archiveBitRate,
            AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue,
        ]
    }

    /// Used when the device rejects AAC. 16-bit PCM at the same rate is still full bandwidth.
    static func losslessArchiveSettings(sampleRate: Double = archiveSampleRate) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }

    static func makeArchiveFile(in directory: URL, sampleRate: Double) throws -> (url: URL, file: AVAudioFile) {
        let id = UUID().uuidString
        let aacURL = directory.appendingPathComponent(id + ".m4a")
        do {
            let file = try AVAudioFile(forWriting: aacURL, settings: archiveFileSettings(sampleRate: sampleRate))
            return (aacURL, file)
        } catch {
            try? FileManager.default.removeItem(at: aacURL)
            let cafURL = directory.appendingPathComponent(id + ".caf")
            let file = try AVAudioFile(forWriting: cafURL, settings: losslessArchiveSettings(sampleRate: sampleRate))
            return (cafURL, file)
        }
    }

    /// Headroom past `inputFrames * ratio` so the max-quality resampler can finish the buffer
    /// instead of dropping the tail of every callback (those drops sound like crackle).
    static func outputFrameCapacity(inputFrames: Int, sourceSampleRate: Double, targetSampleRate: Double) -> Int {
        let ratio = targetSampleRate / max(sourceSampleRate, 1)
        return Int(ceil(Double(max(inputFrames, 0)) * ratio)) + 256
    }

    static func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs == rhs
    }
}

enum RecordingPCMConverter {
    static func convert(_ input: AVAudioPCMBuffer, using converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let format = converter.outputFormat
        let capacity = RecordingAudioSettings.outputFrameCapacity(
            inputFrames: Int(input.frameLength),
            sourceSampleRate: input.format.sampleRate,
            targetSampleRate: format.sampleRate
        )
        guard capacity > 0,
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(capacity))
        else { return nil }

        var error: NSError?
        var providedInput = false
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if providedInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            providedInput = true
            outStatus.pointee = .haveData
            return input
        }
        guard error == nil, status != .error, output.frameLength > 0 else { return nil }
        return output
    }
}
