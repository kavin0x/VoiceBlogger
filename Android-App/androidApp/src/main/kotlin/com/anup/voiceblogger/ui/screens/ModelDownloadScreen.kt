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
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Error
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.anup.voiceblogger.services.DownloadProgress
import com.anup.voiceblogger.services.ModelDownloadManager
import kotlinx.coroutines.launch

@Composable
fun ModelDownloadScreen(
    downloadManager: ModelDownloadManager,
    onComplete: () -> Unit
) {
    val status by downloadManager.status.collectAsState()
    val scope = rememberCoroutineScope()
    var hfToken by remember { mutableStateOf("") }
    var showTokenField by remember { mutableStateOf(false) }

    LaunchedEffect(status.allModelsReady) {
        if (status.allModelsReady) {
            // Small delay so user sees the complete state
            kotlinx.coroutines.delay(800)
            onComplete()
        }
    }

    Surface(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.height(48.dp))

            Text(
                "Downloading AI Models",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                "These models run entirely on your device.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
            )

            Spacer(modifier = Modifier.height(32.dp))

            // Whisper model
            ModelDownloadCard(
                name = "Advanced Speech Recognition",
                size = "~1.5 GB",
                progress = status.whisperProgress,
                available = status.whisperAvailable,
                error = status.whisperError,
                onDownload = {
                    scope.launch { downloadManager.downloadWhisper(hfToken.ifBlank { null }) }
                }
            )

            Spacer(modifier = Modifier.height(16.dp))

            // LLM model
            ModelDownloadCard(
                name = "Blog Generator",
                size = "~1.6 GB",
                progress = status.llmProgress,
                available = status.llmAvailable,
                error = status.llmError,
                onDownload = {
                    if (status.llmError?.contains("HuggingFace") == true && hfToken.isBlank()) {
                        showTokenField = true
                    } else {
                        scope.launch { downloadManager.downloadLLM(hfToken.ifBlank { null }) }
                    }
                }
            )

            if (showTokenField || status.llmError?.contains("HuggingFace") == true) {
                Spacer(modifier = Modifier.height(16.dp))
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer
                    )
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(
                            "HuggingFace Token Required",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.Bold
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            "Visit huggingface.co/onnx-community/Qwen2.5-2B-Instruct to get access, then paste your HF token below.",
                            style = MaterialTheme.typography.bodySmall
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        OutlinedTextField(
                            value = hfToken,
                            onValueChange = { hfToken = it },
                            label = { Text("HuggingFace Token") },
                            visualTransformation = PasswordVisualTransformation(),
                            modifier = Modifier.fillMaxWidth(),
                            singleLine = true
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Button(
                            onClick = {
                                scope.launch { downloadManager.downloadLLM(hfToken.ifBlank { null }) }
                            },
                            modifier = Modifier.fillMaxWidth(),
                            enabled = hfToken.isNotBlank()
                        ) {
                            Text("Download with Token")
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            if (status.allModelsReady) {
                Button(onClick = onComplete, modifier = Modifier.fillMaxWidth()) {
                    Text("Continue")
                }
            } else if (!isDownloading(status.whisperProgress, status.llmProgress)) {
                Button(
                    onClick = {
                        scope.launch {
                            if (!status.whisperAvailable) downloadManager.downloadWhisper(hfToken.ifBlank { null })
                            if (!status.llmAvailable) downloadManager.downloadLLM(hfToken.ifBlank { null })
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(Icons.Default.Download, contentDescription = null)
                        Text("Download Models")
                    }
                }
            }
        }
    }
}

private fun isDownloading(vararg progresses: DownloadProgress): Boolean {
    return progresses.any { it.bytesDownloaded > 0 && !it.isComplete && it.error == null }
}

@Composable
private fun ModelDownloadCard(
    name: String,
    size: String,
    progress: DownloadProgress,
    available: Boolean,
    error: String?,
    onDownload: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text(size, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                }
                when {
                    available -> Icon(
                        Icons.Default.CheckCircle,
                        contentDescription = "Available",
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(24.dp)
                    )
                    error != null -> Icon(
                        Icons.Default.Error,
                        contentDescription = "Error",
                        tint = MaterialTheme.colorScheme.error,
                        modifier = Modifier.size(24.dp)
                    )
                    progress.bytesDownloaded > 0 && !progress.isComplete -> CircularProgressIndicator(
                        modifier = Modifier.size(24.dp),
                        strokeWidth = 2.dp
                    )
                }
            }

            if (!available && progress.bytesDownloaded > 0 && !progress.isComplete) {
                Spacer(modifier = Modifier.height(12.dp))
                LinearProgressIndicator(
                    progress = { progress.fraction },
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(modifier = Modifier.height(4.dp))
                val mb = progress.bytesDownloaded / (1024 * 1024)
                val totalMb = if (progress.totalBytes > 0) progress.totalBytes / (1024 * 1024) else 0
                Text(
                    if (totalMb > 0) "$mb MB / $totalMb MB" else "$mb MB downloaded",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                )
            }

            if (error != null && !error.contains("HuggingFace")) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    error,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
                Spacer(modifier = Modifier.height(8.dp))
                TextButton(onClick = onDownload) {
                    Text("Retry")
                }
            }
        }
    }
}
