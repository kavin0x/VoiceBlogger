package com.anup.voiceblogger.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.anup.voiceblogger.data.BlogPost
import com.anup.voiceblogger.data.BlogPostRepository
import com.anup.voiceblogger.data.TranscriptionState
import com.anup.voiceblogger.services.TranscriptionService
import kotlinx.coroutines.launch
import java.io.File

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TranscriptionScreen(
    post: BlogPost,
    transcriptionService: TranscriptionService,
    repository: BlogPostRepository,
    onBack: () -> Unit,
    onGenerateBlog: (BlogPost) -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var currentPost by remember { mutableStateOf(post) }
    var isTranscribing by remember { mutableStateOf(false) }
    var editedTranscript by remember { mutableStateOf(post.transcript) }
    var isEdited by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val showCrashBanner = post.transcriptionStateEnum == TranscriptionState.IN_PROGRESS

    fun doTranscribe() {
        scope.launch {
            isTranscribing = true
            error = null
            val audioFile = File(File(context.filesDir, "recordings"), currentPost.audioFilename ?: "")
            if (!audioFile.exists()) {
                error = "Audio file not found."
                isTranscribing = false
                return@launch
            }
            // Mark in-progress
            val inProgress = currentPost.withTranscriptionState(TranscriptionState.IN_PROGRESS)
            repository.updatePost(inProgress)
            currentPost = inProgress

            try {
                val text = transcriptionService.transcribe(audioFile)
                val completed = currentPost.copy(
                    transcript = text,
                    transcriptionState = TranscriptionState.COMPLETE.name
                )
                repository.updatePost(completed)
                currentPost = completed
                editedTranscript = text
                isEdited = false
            } catch (e: Exception) {
                error = "Transcription failed: ${e.message}"
                val failed = currentPost.withTranscriptionState(TranscriptionState.UNTRANSCRIBED)
                repository.updatePost(failed)
                currentPost = failed
            }
            isTranscribing = false
        }
    }

    // Auto-start transcription if untranscribed
    LaunchedEffect(Unit) {
        if (currentPost.transcriptionStateEnum == TranscriptionState.UNTRANSCRIBED) {
            doTranscribe()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Transcription") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        }
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .padding(innerPadding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Crash recovery banner
            if (showCrashBanner) {
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer
                    )
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(Icons.Default.Warning, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                        Text(
                            "Transcription was interrupted. Tap Re-transcribe to try again.",
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                }
            }

            // Error message
            error?.let {
                Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer)) {
                    Text(
                        it,
                        modifier = Modifier.padding(12.dp),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onErrorContainer
                    )
                }
            }

            // Progress / content
            if (isTranscribing) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    CircularProgressIndicator()
                    Spacer(modifier = Modifier.height(8.dp))
                    Text("Transcribing...", style = MaterialTheme.typography.bodyMedium)
                    Spacer(modifier = Modifier.height(8.dp))
                    LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                }
            } else {
                // Transcript editor
                OutlinedTextField(
                    value = editedTranscript,
                    onValueChange = { newText ->
                        editedTranscript = newText
                        isEdited = newText != currentPost.transcript
                    },
                    label = { Text("Transcript") },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(240.dp),
                    enabled = currentPost.transcriptionStateEnum == TranscriptionState.COMPLETE || error != null
                )
            }

            // Buttons
            if (isEdited) {
                Button(
                    onClick = {
                        val saved = currentPost.copy(transcript = editedTranscript)
                        repository.updatePost(saved)
                        currentPost = saved
                        isEdited = false
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Save Transcript")
                }
            }

            Button(
                onClick = { onGenerateBlog(currentPost) },
                modifier = Modifier.fillMaxWidth(),
                enabled = editedTranscript.isNotBlank() && !isTranscribing
            ) {
                Text("Generate Blog Post")
            }

            OutlinedButton(
                onClick = { doTranscribe() },
                modifier = Modifier.fillMaxWidth(),
                enabled = !isTranscribing && (currentPost.audioFilename != null)
            ) {
                Text("Re-transcribe")
            }
        }
    }
}
