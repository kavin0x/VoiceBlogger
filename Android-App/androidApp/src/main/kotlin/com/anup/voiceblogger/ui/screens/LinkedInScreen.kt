package com.anup.voiceblogger.ui.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Share
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
import com.anup.voiceblogger.data.BlogPost
import com.anup.voiceblogger.data.BlogPostRepository
import com.anup.voiceblogger.services.LLMService
import com.anup.voiceblogger.utils.PromptBuilder
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LinkedInScreen(
    post: BlogPost,
    llmService: LLMService,
    repository: BlogPostRepository,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var currentPost by remember { mutableStateOf(post) }
    var isGenerating by remember { mutableStateOf(false) }

    fun generatePost() {
        scope.launch {
            isGenerating = true
            val prompt = PromptBuilder.formatQwenPrompt(
                PromptBuilder.linkedinSystemPrompt,
                PromptBuilder.buildLinkedInUserPrompt(currentPost.blogContent)
            )
            val builder = StringBuilder()
            try {
                llmService.generateStream(prompt, PromptBuilder.linkedinMaxTokens()).collect { chunk ->
                    builder.append(chunk)
                    val updated = currentPost.copy(linkedinPost = builder.toString())
                    repository.updatePost(updated)
                    currentPost = updated
                }
            } catch (e: Exception) {
                // partial result
            }
            isGenerating = false
        }
    }

    LaunchedEffect(Unit) {
        if (currentPost.linkedinPost.isBlank()) {
            generatePost()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("LinkedIn") },
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
        ) {
            if (isGenerating) {
                LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
            }

            if (isGenerating && currentPost.linkedinPost.isBlank()) {
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator()
                }
            } else {
                Card(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .padding(16.dp),
                    elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)
                ) {
                    Text(
                        text = currentPost.linkedinPost,
                        modifier = Modifier
                            .fillMaxSize()
                            .verticalScroll(rememberScrollState())
                            .padding(16.dp),
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }

            // Copy and Share buttons
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedButton(
                    onClick = {
                        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        clipboard.setPrimaryClip(ClipData.newPlainText("LinkedIn Post", currentPost.linkedinPost))
                        Toast.makeText(context, "Copied to clipboard", Toast.LENGTH_SHORT).show()
                    },
                    modifier = Modifier.weight(1f)
                ) {
                    Icon(Icons.Default.ContentCopy, contentDescription = null, modifier = Modifier.padding(end = 4.dp))
                    Text("Copy")
                }
                Button(
                    onClick = {
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, currentPost.linkedinPost)
                        }
                        context.startActivity(Intent.createChooser(intent, "Share Post"))
                    },
                    modifier = Modifier.weight(1f)
                ) {
                    Icon(Icons.Default.Share, contentDescription = null, modifier = Modifier.padding(end = 4.dp))
                    Text("Share")
                }
            }
        }
    }
}
