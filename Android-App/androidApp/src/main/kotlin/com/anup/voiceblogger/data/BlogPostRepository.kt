package com.anup.voiceblogger.data

import android.content.Context
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

class BlogPostRepository(private val context: Context) {

    private val postsDir: File
        get() = File(context.filesDir, "posts").also { it.mkdirs() }

    private val manifestFile: File
        get() = File(context.filesDir, "posts_manifest.json")

    private val json = Json { ignoreUnknownKeys = true }

    private fun readManifest(): MutableList<String> {
        return try {
            if (manifestFile.exists()) {
                json.decodeFromString<List<String>>(manifestFile.readText()).toMutableList()
            } else {
                mutableListOf()
            }
        } catch (e: Exception) {
            mutableListOf()
        }
    }

    private fun writeManifest(ids: List<String>) {
        manifestFile.writeText(json.encodeToString(ids))
    }

    fun savePost(post: BlogPost) {
        val file = File(postsDir, "${post.id}.json")
        file.writeText(json.encodeToString(post))
        val manifest = readManifest()
        if (!manifest.contains(post.id)) {
            manifest.add(0, post.id) // newest first
            writeManifest(manifest)
        }
    }

    fun getPost(id: String): BlogPost? {
        return try {
            val file = File(postsDir, "$id.json")
            if (file.exists()) {
                json.decodeFromString<BlogPost>(file.readText())
            } else null
        } catch (e: Exception) {
            null
        }
    }

    fun getAllPosts(): List<BlogPost> {
        val manifest = readManifest()
        return manifest.mapNotNull { getPost(it) }
    }

    fun deletePost(id: String) {
        File(postsDir, "$id.json").delete()
        val manifest = readManifest()
        manifest.remove(id)
        writeManifest(manifest)
    }

    fun updatePost(post: BlogPost) {
        val file = File(postsDir, "${post.id}.json")
        file.writeText(json.encodeToString(post))
    }

    fun recoverInProgressPosts(): List<BlogPost> {
        return getAllPosts().filter {
            it.transcriptionStateEnum == TranscriptionState.IN_PROGRESS
        }
    }
}
