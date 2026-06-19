package com.anup.voiceblogger

import android.app.Application
import com.anup.voiceblogger.data.BlogPostRepository
import com.anup.voiceblogger.services.AudioRecorderService
import com.anup.voiceblogger.services.LLMService
import com.anup.voiceblogger.services.ModelDownloadManager
import com.anup.voiceblogger.services.TranscriptionService

class VoiceBloggerApplication : Application() {

    lateinit var repository: BlogPostRepository
        private set

    lateinit var audioRecorderService: AudioRecorderService
        private set

    lateinit var transcriptionService: TranscriptionService
        private set

    lateinit var llmService: LLMService
        private set

    lateinit var modelDownloadManager: ModelDownloadManager
        private set

    override fun onCreate() {
        super.onCreate()
        instance = this
        repository = BlogPostRepository(this)
        audioRecorderService = AudioRecorderService(this)
        transcriptionService = TranscriptionService(this)
        llmService = LLMService(this)
        modelDownloadManager = ModelDownloadManager(this)
        modelDownloadManager.checkModels()
    }

    companion object {
        lateinit var instance: VoiceBloggerApplication
            private set
    }
}
