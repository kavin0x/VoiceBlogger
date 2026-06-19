package com.anup.voiceblogger.services

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

data class DownloadProgress(
    val bytesDownloaded: Long = 0L,
    val totalBytes: Long = -1L,
    val isComplete: Boolean = false,
    val error: String? = null
) {
    val fraction: Float
        get() = if (totalBytes > 0) bytesDownloaded.toFloat() / totalBytes.toFloat() else 0f
}

data class ModelStatus(
    val whisperAvailable: Boolean = false,
    val llmAvailable: Boolean = false,
    val whisperProgress: DownloadProgress = DownloadProgress(),
    val llmProgress: DownloadProgress = DownloadProgress(),
    val whisperError: String? = null,
    val llmError: String? = null
) {
    val allModelsReady: Boolean get() = whisperAvailable && llmAvailable
}

class ModelDownloadManager(private val context: Context) {

    companion object {
        private const val WHISPER_URL =
            "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-medium.tar.bz2"

        private const val LLM_BASE_URL =
            "https://huggingface.co/onnx-community/Qwen2.5-2B-Instruct/resolve/main"

        // Files required by ORT GenAI — downloaded individually
        private val LLM_FILES = listOf(
            "genai_config.json",
            "tokenizer.json",
            "tokenizer_config.json",
            "special_tokens_map.json",
            "model.onnx",
            "model.onnx.data"
        )
    }

    private val _status = MutableStateFlow(ModelStatus())
    val status: StateFlow<ModelStatus> = _status.asStateFlow()

    private val whisperDir: File
        get() = File(context.filesDir, "models/whisper").also { it.mkdirs() }

    private val llmDir: File
        get() = File(context.filesDir, "models/llm/qwen2.5-2b").also { it.mkdirs() }

    fun checkModels() {
        val whisperAvailable =
            File(whisperDir, "sherpa-onnx-whisper-medium/encoder.int8.onnx").exists() &&
            File(whisperDir, "sherpa-onnx-whisper-medium/decoder.int8.onnx").exists() &&
            File(whisperDir, "sherpa-onnx-whisper-medium/tokens.txt").exists()

        val llmAvailable =
            File(llmDir, "genai_config.json").exists() &&
            File(llmDir, "model.onnx.data").exists()

        _status.value = _status.value.copy(
            whisperAvailable = whisperAvailable,
            llmAvailable = llmAvailable,
            whisperProgress = if (whisperAvailable) DownloadProgress(isComplete = true) else _status.value.whisperProgress,
            llmProgress = if (llmAvailable) DownloadProgress(isComplete = true) else _status.value.llmProgress,
        )
    }

    suspend fun downloadWhisper(hfToken: String? = null) {
        val archiveFile = File(whisperDir, "whisper_medium.tar.bz2")
        try {
            downloadFile(WHISPER_URL, archiveFile, hfToken) { progress ->
                _status.value = _status.value.copy(whisperProgress = progress, whisperError = null)
            }
            // Extract the archive
            _status.value = _status.value.copy(
                whisperProgress = _status.value.whisperProgress.copy(isComplete = false)
            )
            extractTarBz2(archiveFile, whisperDir)
            archiveFile.delete()
            _status.value = _status.value.copy(
                whisperAvailable = true,
                whisperProgress = DownloadProgress(isComplete = true)
            )
        } catch (e: Exception) {
            archiveFile.delete()
            _status.value = _status.value.copy(
                whisperError = e.message ?: "Download failed",
                whisperProgress = DownloadProgress()
            )
        }
    }

    suspend fun downloadLLM(hfToken: String? = null) {
        // model.onnx.data is ~1.5 GB; other files are negligible
        val estimatedTotal = 1_600_000_000L
        var totalDownloaded = LLM_FILES
            .map { File(llmDir, it) }
            .filter { it.exists() }
            .sumOf { it.length() }

        try {
            for (filename in LLM_FILES) {
                val outFile = File(llmDir, filename)
                if (outFile.exists()) continue
                val fileStart = totalDownloaded
                downloadFile("$LLM_BASE_URL/$filename", outFile, hfToken) { p ->
                    _status.value = _status.value.copy(
                        llmProgress = DownloadProgress(fileStart + p.bytesDownloaded, estimatedTotal),
                        llmError = null
                    )
                }
                totalDownloaded += outFile.length()
            }
            _status.value = _status.value.copy(
                llmAvailable = true,
                llmProgress = DownloadProgress(isComplete = true)
            )
        } catch (e: Exception) {
            val msg = e.message ?: "Download failed"
            if (msg.contains("401") || msg.contains("403")) {
                _status.value = _status.value.copy(
                    llmError = "HuggingFace token required. " +
                            "Visit huggingface.co/onnx-community/Qwen2.5-2B-Instruct and paste your token below.",
                    llmProgress = DownloadProgress()
                )
            } else {
                _status.value = _status.value.copy(
                    llmError = msg,
                    llmProgress = DownloadProgress()
                )
            }
        }
    }

    private suspend fun downloadFile(
        urlString: String,
        outputFile: File,
        hfToken: String?,
        onProgress: (DownloadProgress) -> Unit
    ) = withContext(Dispatchers.IO) {
        val url = URL(urlString)
        val connection = url.openConnection() as HttpURLConnection
        connection.connectTimeout = 30000
        connection.readTimeout = 60000

        if (hfToken != null) {
            connection.setRequestProperty("Authorization", "Bearer $hfToken")
        }

        val responseCode = connection.responseCode
        if (responseCode == 401 || responseCode == 403) {
            connection.disconnect()
            throw Exception("HTTP $responseCode: Authentication required")
        }
        if (responseCode != HttpURLConnection.HTTP_OK) {
            connection.disconnect()
            throw Exception("HTTP error: $responseCode")
        }

        val totalBytes = connection.contentLengthLong

        connection.inputStream.use { inputStream ->
            outputFile.outputStream().use { outputStream ->
                val buffer = ByteArray(8192)
                var bytesDownloaded = 0L
                var bytesRead: Int
                while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                    outputStream.write(buffer, 0, bytesRead)
                    bytesDownloaded += bytesRead
                    onProgress(DownloadProgress(bytesDownloaded, totalBytes))
                }
            }
        }
        connection.disconnect()
    }

    private suspend fun extractTarBz2(archive: File, destDir: File) = withContext(Dispatchers.IO) {
        // Pure Java extraction without commons-compress
        // We'll use a manual approach since commons-compress isn't in deps
        // Fall back to Process for bz2 extraction if available, otherwise use a streaming approach
        try {
            extractTarBz2WithStreams(archive, destDir)
        } catch (e: Exception) {
            throw Exception("Failed to extract archive: ${e.message}")
        }
    }

    private fun extractTarBz2WithStreams(archive: File, destDir: File) {
        // Use Apache Commons Compress via reflection if available, otherwise parse manually
        // For now we parse tar.bz2 manually using Java's built-in streams
        // Note: Java doesn't have built-in BZ2. We'll handle via ProcessBuilder (shell decompress)
        val process = ProcessBuilder("sh", "-c",
            "cd ${destDir.absolutePath} && bzip2 -dc ${archive.absolutePath} | tar xf -"
        ).redirectErrorStream(true).start()

        val exitCode = process.waitFor()
        if (exitCode != 0) {
            val error = process.inputStream.bufferedReader().readText()
            throw Exception("Extraction failed (exit $exitCode): $error")
        }
    }

    fun resetModels() {
        whisperDir.deleteRecursively()
        File(context.filesDir, "models/llm").deleteRecursively()
        _status.value = ModelStatus()
        checkModels()
    }
}
