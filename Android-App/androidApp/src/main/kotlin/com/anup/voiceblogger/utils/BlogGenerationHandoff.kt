package com.anup.voiceblogger.utils

import com.anup.voiceblogger.data.BlogPost
import com.anup.voiceblogger.data.BlogPostRepository

/**
 * Handles the handoff between transcription and blog generation.
 * Port of iOS BlogGenerationHandoff.swift.
 */
object BlogGenerationHandoff {

    /**
     * Prepares a post for blog generation after transcription is complete.
     * Updates the post's blog content title based on the transcript if no blog yet.
     */
    fun prepareForGeneration(post: BlogPost, repository: BlogPostRepository): BlogPost {
        // If there's already blog content, return as-is
        if (post.blogContent.isNotBlank()) return post

        // Update transcription state to complete
        val updated = post.withTranscriptionState(com.anup.voiceblogger.data.TranscriptionState.COMPLETE)
        repository.updatePost(updated)
        return updated
    }

    /**
     * Saves generated blog content to the post and updates the repository.
     */
    fun saveBlogContent(post: BlogPost, blogContent: String, repository: BlogPostRepository): BlogPost {
        val updated = post.copy(blogContent = blogContent)
        repository.updatePost(updated)
        return updated
    }

    /**
     * Saves generated Instagram captions to the post.
     */
    fun saveInstagramCaptions(post: BlogPost, captions: String, repository: BlogPostRepository): BlogPost {
        val updated = post.copy(instagramCaptions = captions)
        repository.updatePost(updated)
        return updated
    }

    /**
     * Saves generated LinkedIn post content.
     */
    fun saveLinkedInPost(post: BlogPost, linkedinPost: String, repository: BlogPostRepository): BlogPost {
        val updated = post.copy(linkedinPost = linkedinPost)
        repository.updatePost(updated)
        return updated
    }
}
