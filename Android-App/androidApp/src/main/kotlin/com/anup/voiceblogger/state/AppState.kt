package com.anup.voiceblogger.state

import androidx.lifecycle.ViewModel
import com.anup.voiceblogger.data.BlogPost
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

sealed class AppStage {
    object ModelDownload : AppStage()
    object Onboarding : AppStage()
    object Recording : AppStage()
    data class Transcribing(val post: BlogPost) : AppStage()
    data class PreparingBlog(val postId: String) : AppStage()
    data class GeneratingBlog(val post: BlogPost) : AppStage()
    data class ViewingBlog(val post: BlogPost) : AppStage()
    data class ViewingInstagram(val post: BlogPost) : AppStage()
    data class ViewingLinkedIn(val post: BlogPost) : AppStage()
    object History : AppStage()
    object About : AppStage()
}

class AppStateViewModel : ViewModel() {
    private val _stage = MutableStateFlow<AppStage>(AppStage.ModelDownload)
    val stage: StateFlow<AppStage> = _stage.asStateFlow()

    fun navigateTo(stage: AppStage) {
        _stage.value = stage
    }

    fun goToRecording() {
        _stage.value = AppStage.Recording
    }

    fun goToTranscribing(post: BlogPost) {
        _stage.value = AppStage.Transcribing(post)
    }

    fun goToPreparingBlog(postId: String) {
        _stage.value = AppStage.PreparingBlog(postId)
    }

    fun goToGeneratingBlog(post: BlogPost) {
        _stage.value = AppStage.GeneratingBlog(post)
    }

    fun goToViewingBlog(post: BlogPost) {
        _stage.value = AppStage.ViewingBlog(post)
    }

    fun goToViewingInstagram(post: BlogPost) {
        _stage.value = AppStage.ViewingInstagram(post)
    }

    fun goToViewingLinkedIn(post: BlogPost) {
        _stage.value = AppStage.ViewingLinkedIn(post)
    }

    fun goToHistory() {
        _stage.value = AppStage.History
    }
}
