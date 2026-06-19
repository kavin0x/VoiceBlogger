package com.anup.voiceblogger.services

import android.content.Context
import com.anup.voiceblogger.utils.AudioDecoder
import com.k2fsa.sherpa.onnx.FeatureConfig
import com.k2fsa.sherpa.onnx.OfflineModelConfig
import com.k2fsa.sherpa.onnx.OfflineRecognizer
import com.k2fsa.sherpa.onnx.OfflineRecognizerConfig
import com.k2fsa.sherpa.onnx.OfflineWhisperModelConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

class TranscriptionService(private val context: Context) {

    private val whisperDir: File
        get() = File(context.filesDir, "models/whisper")

    private val encoderPath: String
        get() = File(whisperDir, "sherpa-onnx-whisper-medium/encoder.int8.onnx").absolutePath

    private val decoderPath: String
        get() = File(whisperDir, "sherpa-onnx-whisper-medium/decoder.int8.onnx").absolutePath

    private val tokensPath: String
        get() = File(whisperDir, "sherpa-onnx-whisper-medium/tokens.txt").absolutePath

    fun areModelsAvailable(): Boolean {
        return File(encoderPath).exists() &&
                File(decoderPath).exists() &&
                File(tokensPath).exists()
    }

    suspend fun transcribe(audioFile: File): String = withContext(Dispatchers.IO) {
        val config = OfflineRecognizerConfig(
            featConfig = FeatureConfig(sampleRate = 16000, featureDim = 80),
            modelConfig = OfflineModelConfig(
                whisper = OfflineWhisperModelConfig(
                    encoder = encoderPath,
                    decoder = decoderPath,
                    language = "auto",
                    task = "transcribe",
                    tailPaddings = 1000,
                ),
                tokens = tokensPath,
                numThreads = 2,
                debug = false,
                provider = "cpu",
            ),
            decodingMethod = "greedy_search",
        )

        val recognizer = OfflineRecognizer(config = config)
        try {
            val samples = AudioDecoder.decodeToFloatSamples(audioFile)
            if (samples.isEmpty()) return@withContext ""

            val stream = recognizer.createStream()
            stream.acceptWaveform(samples, sampleRate = 16000)
            recognizer.decode(stream)
            val result = recognizer.getResult(stream)
            stream.release()
            result.text.trim()
        } finally {
            recognizer.release()
        }
    }
}
