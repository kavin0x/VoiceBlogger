package com.anup.voiceblogger.data

import kotlinx.serialization.Serializable

enum class TranscriptionState {
    UNTRANSCRIBED,
    IN_PROGRESS,
    COMPLETE
}

@Serializable
data class BlogPost(
    val id: String,
    val transcript: String = "",
    val blogContent: String = "",
    val instagramCaptions: String = "",
    val linkedinPost: String = "",
    val audioFilename: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
    val duration: Double = 0.0,
    val transcriptionState: String = TranscriptionState.UNTRANSCRIBED.name
) {
    val title: String
        get() = extractTitle(blogContent)

    val transcriptionStateEnum: TranscriptionState
        get() = TranscriptionState.valueOf(transcriptionState)

    private fun extractTitle(content: String): String {
        if (content.isBlank()) return "Untitled Post"
        val firstLine = content.lines().firstOrNull { it.isNotBlank() } ?: return "Untitled Post"
        val withoutHash = firstLine.trimStart('#', ' ')
        val withoutBold = withoutHash.replace(Regex("\\*\\*(.*?)\\*\\*"), "$1")
        return withoutBold.take(80).ifBlank { "Untitled Post" }
    }

    fun withTranscriptionState(state: TranscriptionState): BlogPost =
        copy(transcriptionState = state.name)
}
