package com.anup.voiceblogger.utils

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

object AudioDecoder {

    private const val TARGET_SAMPLE_RATE = 16000

    /**
     * Decodes any audio file to 16kHz mono PCM float samples.
     * Uses MediaExtractor + MediaCodec.
     */
    fun decodeToFloatSamples(file: File): FloatArray {
        val extractor = MediaExtractor()
        extractor.setDataSource(file.absolutePath)

        // Find audio track
        var audioTrackIndex = -1
        var inputFormat: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("audio/")) {
                audioTrackIndex = i
                inputFormat = format
                break
            }
        }
        if (audioTrackIndex < 0 || inputFormat == null) {
            extractor.release()
            return FloatArray(0)
        }

        extractor.selectTrack(audioTrackIndex)
        val mime = inputFormat.getString(MediaFormat.KEY_MIME)!!
        val sourceSampleRate = inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val channelCount = inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)

        val codec = MediaCodec.createDecoderByType(mime)
        codec.configure(inputFormat, null, null, 0)
        codec.start()

        val bufferInfo = MediaCodec.BufferInfo()
        var isEOS = false

        var pcmArray = ShortArray(1024 * 1024)
        var pcmSize = 0

        while (!isEOS) {
            // Feed input
            val inputBufferIndex = codec.dequeueInputBuffer(10000)
            if (inputBufferIndex >= 0) {
                val inputBuffer: ByteBuffer = codec.getInputBuffer(inputBufferIndex)!!
                val sampleSize = extractor.readSampleData(inputBuffer, 0)
                if (sampleSize < 0) {
                    codec.queueInputBuffer(inputBufferIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                } else {
                    val presentationTimeUs = extractor.sampleTime
                    codec.queueInputBuffer(inputBufferIndex, 0, sampleSize, presentationTimeUs, 0)
                    extractor.advance()
                }
            }

            // Drain output
            var outputBufferIndex = codec.dequeueOutputBuffer(bufferInfo, 10000)
            while (outputBufferIndex >= 0) {
                val outputBuffer: ByteBuffer = codec.getOutputBuffer(outputBufferIndex)!!
                outputBuffer.order(ByteOrder.LITTLE_ENDIAN)
                val shortsCount = outputBuffer.remaining() / 2
                if (pcmSize + shortsCount > pcmArray.size) {
                    pcmArray = pcmArray.copyOf(maxOf(pcmSize + shortsCount, pcmArray.size * 2))
                }
                outputBuffer.asShortBuffer().get(pcmArray, pcmSize, shortsCount)
                pcmSize += shortsCount

                codec.releaseOutputBuffer(outputBufferIndex, false)
                if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                    isEOS = true
                    break
                }
                outputBufferIndex = codec.dequeueOutputBuffer(bufferInfo, 0)
            }
        }

        codec.stop()
        codec.release()
        extractor.release()

        val finalPcm = pcmArray.copyOf(pcmSize)

        // Convert shorts to floats, mix to mono
        val monoShorts = if (channelCount > 1) {
            // Average channels
            val mono = ShortArray(finalPcm.size / channelCount)
            for (i in mono.indices) {
                var sum = 0L
                for (c in 0 until channelCount) {
                    sum += finalPcm[i * channelCount + c]
                }
                mono[i] = (sum / channelCount).toShort()
            }
            mono
        } else {
            finalPcm
        }

        // Resample to 16kHz if needed
        val resampledShorts = if (sourceSampleRate != TARGET_SAMPLE_RATE) {
            resample(monoShorts, sourceSampleRate, TARGET_SAMPLE_RATE)
        } else {
            monoShorts
        }

        // Convert to float [-1, 1]
        return FloatArray(resampledShorts.size) { i ->
            resampledShorts[i].toFloat() / 32768f
        }
    }

    private fun resample(samples: ShortArray, fromRate: Int, toRate: Int): ShortArray {
        if (fromRate == toRate) return samples
        val ratio = fromRate.toDouble() / toRate.toDouble()
        val outputSize = (samples.size / ratio).toInt()
        val output = ShortArray(outputSize)
        for (i in 0 until outputSize) {
            val srcIndex = (i * ratio).toInt().coerceIn(0, samples.size - 1)
            output[i] = samples[srcIndex]
        }
        return output
    }
}
