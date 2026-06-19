package com.anup.voiceblogger.ui.screens

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Box
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
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.anup.voiceblogger.data.BlogPost
import com.anup.voiceblogger.data.BlogPostRepository
import com.anup.voiceblogger.services.LLMService
import com.anup.voiceblogger.ui.components.MarkdownView
import com.anup.voiceblogger.utils.PromptBuilder
import kotlinx.coroutines.launch
import java.io.File

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BlogScreen(
    post: BlogPost,
    llmService: LLMService,
    repository: BlogPostRepository,
    onNewRecording: () -> Unit,
    onOpenInstagram: (BlogPost) -> Unit,
    onOpenLinkedIn: (BlogPost) -> Unit,
    onOpenHistory: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var currentPost by remember { mutableStateOf(post) }
    var isGenerating by remember { mutableStateOf(false) }
    var isEditMode by remember { mutableStateOf(false) }
    var editedContent by remember { mutableStateOf(post.blogContent) }
    var showMenu by remember { mutableStateOf(false) }

    fun generateBlog() {
        scope.launch {
            isGenerating = true
            val prompt = PromptBuilder.formatQwenPrompt(
                PromptBuilder.blogSystemPrompt,
                PromptBuilder.buildBlogUserPrompt(currentPost.transcript)
            )
            val builder = StringBuilder()
            try {
                llmService.generateStream(prompt, PromptBuilder.blogMaxTokens()).collect { chunk ->
                    builder.append(chunk)
                    val updated = currentPost.copy(blogContent = builder.toString())
                    repository.updatePost(updated)
                    currentPost = updated
                    editedContent = builder.toString()
                }
            } catch (e: Exception) {
                // Partial result is still saved
            }
            isGenerating = false
        }
    }

    LaunchedEffect(Unit) {
        if (currentPost.blogContent.isBlank()) {
            generateBlog()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(currentPost.title.take(30)) },
                navigationIcon = {
                    IconButton(onClick = onNewRecording) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "New Recording")
                    }
                },
                actions = {
                    if (isEditMode) {
                        IconButton(onClick = {
                            val updated = currentPost.copy(blogContent = editedContent)
                            repository.updatePost(updated)
                            currentPost = updated
                            isEditMode = false
                        }) {
                            Icon(Icons.Default.Edit, contentDescription = "Save")
                        }
                    }
                    Box {
                        IconButton(onClick = { showMenu = true }) {
                            Icon(Icons.Default.MoreVert, contentDescription = "More")
                        }
                        DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                            DropdownMenuItem(
                                text = { Text(if (isEditMode) "View" else "Edit") },
                                onClick = {
                                    showMenu = false
                                    if (isEditMode) {
                                        val updated = currentPost.copy(blogContent = editedContent)
                                        repository.updatePost(updated)
                                        currentPost = updated
                                    }
                                    isEditMode = !isEditMode
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("Share Blog") },
                                onClick = {
                                    showMenu = false
                                    val intent = Intent(Intent.ACTION_SEND).apply {
                                        type = "text/plain"
                                        putExtra(Intent.EXTRA_TEXT, currentPost.blogContent)
                                    }
                                    context.startActivity(Intent.createChooser(intent, "Share Blog"))
                                }
                            )
                            if (currentPost.audioFilename != null) {
                                DropdownMenuItem(
                                    text = { Text("Share Audio") },
                                    onClick = {
                                        showMenu = false
                                        val audioFile = File(
                                            File(context.filesDir, "recordings"),
                                            currentPost.audioFilename!!
                                        )
                                        if (audioFile.exists()) {
                                            val uri = FileProvider.getUriForFile(
                                                context,
                                                "com.anup.voiceblogger.fileprovider",
                                                audioFile
                                            )
                                            val intent = Intent(Intent.ACTION_SEND).apply {
                                                type = "audio/*"
                                                putExtra(Intent.EXTRA_STREAM, uri)
                                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                            }
                                            context.startActivity(Intent.createChooser(intent, "Share Audio"))
                                        }
                                    }
                                )
                            }
                            DropdownMenuItem(
                                text = { Text("Save Transcript") },
                                onClick = {
                                    showMenu = false
                                    val intent = Intent(Intent.ACTION_SEND).apply {
                                        type = "text/plain"
                                        putExtra(Intent.EXTRA_TEXT, currentPost.transcript)
                                    }
                                    context.startActivity(Intent.createChooser(intent, "Save Transcript"))
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("Regenerate Blog") },
                                onClick = {
                                    showMenu = false
                                    generateBlog()
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("History") },
                                onClick = { showMenu = false; onOpenHistory() }
                            )
                        }
                    }
                }
            )
        }
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .padding(innerPadding)
                .fillMaxSize()
        ) {
            if (isGenerating) {
                LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
            }

            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
            ) {
                if (isEditMode) {
                    OutlinedTextField(
                        value = editedContent,
                        onValueChange = { editedContent = it },
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(16.dp)
                    )
                } else {
                    if (currentPost.blogContent.isNotBlank()) {
                        MarkdownView(
                            markdown = currentPost.blogContent,
                            modifier = Modifier
                                .fillMaxSize()
                                .verticalScroll(rememberScrollState())
                                .padding(16.dp)
                        )
                    } else if (isGenerating) {
                        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator()
                        }
                    }
                }
            }

            // Bottom buttons
            Column(modifier = Modifier.padding(16.dp)) {
                Button(
                    onClick = { onOpenInstagram(currentPost) },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = currentPost.blogContent.isNotBlank() && !isGenerating
                ) {
                    Text("Instagram")
                }
                Spacer(modifier = Modifier.height(8.dp))
                Button(
                    onClick = { onOpenLinkedIn(currentPost) },
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.secondaryContainer,
                        contentColor = MaterialTheme.colorScheme.onSecondaryContainer
                    ),
                    enabled = currentPost.blogContent.isNotBlank() && !isGenerating
                ) {
                    Text("LinkedIn")
                }
            }
        }
    }
}
