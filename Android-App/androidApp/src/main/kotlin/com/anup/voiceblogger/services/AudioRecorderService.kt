package com.anup.voiceblogger.services

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File

data class RecordingState(
    val isRecording: Boolean = false,
    val durationSeconds: Int = 0,
    val amplitudeLevel: Float = 0f,
    val outputFile: File? = null,
    val error: String? = null
)

class AudioRecorderService(private val context: Context) {

    private var mediaRecorder: MediaRecorder? = null
    private var currentOutputFile: File? = null
    private var recordingStartTime: Long = 0L

    private val _state = MutableStateFlow(RecordingState())
    val state: StateFlow<RecordingState> = _state.asStateFlow()

    private val recordingsDir: File
        get() = File(context.filesDir, "recordings").also { it.mkdirs() }

    fun startRecording(): Boolean {
        return try {
            val timestamp = System.currentTimeMillis()
            val outputFile = File(recordingsDir, "recording_$timestamp.m4a")
            currentOutputFile = outputFile

            val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(context)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }

            recorder.apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioSamplingRate(16000)
                setAudioChannels(1)
                setAudioEncodingBitRate(64000)
                setOutputFile(outputFile.absolutePath)
                prepare()
                start()
            }

            mediaRecorder = recorder
            recordingStartTime = System.currentTimeMillis()

            _state.value = RecordingState(
                isRecording = true,
                outputFile = outputFile
            )
            true
        } catch (e: Exception) {
            _state.value = _state.value.copy(error = e.message, isRecording = false)
            false
        }
    }

    fun stopRecording(): File? {
        val recorder = mediaRecorder ?: return null
        return try {
            recorder.stop()
            recorder.release()
            mediaRecorder = null

            val outputFile = currentOutputFile
            _state.value = RecordingState(isRecording = false, outputFile = outputFile)
            outputFile
        } catch (e: Exception) {
            mediaRecorder?.release()
            mediaRecorder = null
            _state.value = RecordingState(isRecording = false, error = e.message)
            null
        }
    }

    fun getAmplitude(): Int {
        return try {
            mediaRecorder?.maxAmplitude ?: 0
        } catch (e: Exception) {
            0
        }
    }

    fun getDurationSeconds(): Int {
        if (!_state.value.isRecording) return 0
        return ((System.currentTimeMillis() - recordingStartTime) / 1000).toInt()
    }

    fun release() {
        mediaRecorder?.release()
        mediaRecorder = null
    }
}
