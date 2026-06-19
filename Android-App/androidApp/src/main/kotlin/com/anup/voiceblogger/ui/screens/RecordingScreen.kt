package com.anup.voiceblogger.ui.screens

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.UploadFile
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.anup.voiceblogger.data.BlogPost
import com.anup.voiceblogger.data.BlogPostRepository
import com.anup.voiceblogger.data.TranscriptionState
import com.anup.voiceblogger.services.AudioRecorderService
import com.anup.voiceblogger.ui.components.WaveformView
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import java.util.UUID

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecordingScreen(
    recorder: AudioRecorderService,
    repository: BlogPostRepository,
    onStartTranscription: (BlogPost) -> Unit,
    onOpenHistory: () -> Unit,
    onOpenAbout: () -> Unit,
    onResetModels: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var isRecording by remember { mutableStateOf(false) }
    var durationSeconds by remember { mutableIntStateOf(0) }
    var amplitudeLevels = remember { mutableStateListOf<Float>() }
    var showMenu by remember { mutableStateOf(false) }
    var permissionDenied by remember { mutableStateOf(false) }

    // Init waveform levels
    LaunchedEffect(Unit) {
        repeat(30) { amplitudeLevels.add(0.05f) }
    }

    // Amplitude polling while recording
    LaunchedEffect(isRecording) {
        if (isRecording) {
            while (isRecording) {
                val rawAmp = recorder.getAmplitude()
                val normalized = (rawAmp / 32768f).coerceIn(0f, 1f)
                durationSeconds = recorder.getDurationSeconds()
                if (amplitudeLevels.size >= 30) {
                    amplitudeLevels.removeAt(0)
                }
                amplitudeLevels.add(normalized)
                delay(100)
            }
        }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            val started = recorder.startRecording()
            if (started) isRecording = true
        } else {
            permissionDenied = true
        }
    }

    val filePicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        uri?.let {
            scope.launch {
                // Copy file to internal storage
                val inputStream = context.contentResolver.openInputStream(uri) ?: return@launch
                val ext = context.contentResolver.getType(uri)?.let { mime ->
                    when {
                        mime.contains("mp3") -> ".mp3"
                        mime.contains("mp4") || mime.contains("m4a") -> ".m4a"
                        mime.contains("ogg") -> ".ogg"
                        mime.contains("wav") -> ".wav"
                        else -> ".audio"
                    }
                } ?: ".audio"
                val destFile = File(
                    File(context.filesDir, "recordings").also { it.mkdirs() },
                    "imported_${System.currentTimeMillis()}$ext"
                )
                destFile.outputStream().use { out -> inputStream.copyTo(out) }

                val post = BlogPost(
                    id = UUID.randomUUID().toString(),
                    audioFilename = destFile.name,
                    transcriptionState = TranscriptionState.UNTRANSCRIBED.name,
                    createdAt = System.currentTimeMillis()
                )
                repository.savePost(post)
                onStartTranscription(post)
            }
        }
    }

    DisposableEffect(Unit) {
        onDispose { recorder.release() }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("VoiceBlogger") },
                actions = {
                    IconButton(onClick = onOpenHistory) {
                        Icon(Icons.Default.History, contentDescription = "History")
                    }
                    Box {
                        IconButton(onClick = { showMenu = true }) {
                            Icon(Icons.Default.MoreVert, contentDescription = "More")
                        }
                        DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                            DropdownMenuItem(
                                text = { Text("About") },
                                onClick = { showMenu = false; onOpenAbout() }
                            )
                            DropdownMenuItem(
                                text = { Text("Reset & Re-download Models") },
                                onClick = { showMenu = false; onResetModels() }
                            )
                        }
                    }
                }
            )
        }
    ) { innerPadding ->
        if (permissionDenied) {
            PermissionDeniedContent(
                modifier = Modifier
                    .padding(innerPadding)
                    .fillMaxSize()
            )
        } else {
            Column(
                modifier = Modifier
                    .padding(innerPadding)
                    .fillMaxSize()
                    .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                if (isRecording) {
                    // Duration timer
                    val minutes = durationSeconds / 60
                    val secs = durationSeconds % 60
                    Text(
                        "%02d:%02d".format(minutes, secs),
                        style = MaterialTheme.typography.displaySmall,
                        fontWeight = FontWeight.Light,
                        fontSize = 48.sp
                    )
                    Spacer(modifier = Modifier.height(24.dp))
                }

                // Waveform
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(100.dp)
                ) {
                    WaveformView(amplitudeLevels = amplitudeLevels)
                }

                Spacer(modifier = Modifier.height(40.dp))

                // Record / Stop button
                FilledIconButton(
                    onClick = {
                        if (isRecording) {
                            val file = recorder.stopRecording()
                            isRecording = false
                            if (file != null) {
                                val post = BlogPost(
                                    id = UUID.randomUUID().toString(),
                                    audioFilename = file.name,
                                    transcriptionState = TranscriptionState.UNTRANSCRIBED.name,
                                    duration = durationSeconds.toDouble(),
                                    createdAt = System.currentTimeMillis()
                                )
                                repository.savePost(post)
                                onStartTranscription(post)
                            }
                        } else {
                            val perm = Manifest.permission.RECORD_AUDIO
                            val granted = ContextCompat.checkSelfPermission(context, perm) ==
                                    android.content.pm.PackageManager.PERMISSION_GRANTED
                            if (granted) {
                                val started = recorder.startRecording()
                                if (started) isRecording = true
                            } else {
                                permissionLauncher.launch(perm)
                            }
                        }
                    },
                    modifier = Modifier.size(80.dp),
                    shape = CircleShape
                ) {
                    Icon(
                        if (isRecording) Icons.Default.Stop else Icons.Default.Mic,
                        contentDescription = if (isRecording) "Stop" else "Record",
                        modifier = Modifier.size(36.dp)
                    )
                }

                Spacer(modifier = Modifier.height(24.dp))

                if (!isRecording) {
                    Button(
                        onClick = { filePicker.launch(arrayOf("audio/*")) },
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.secondaryContainer,
                            contentColor = MaterialTheme.colorScheme.onSecondaryContainer
                        )
                    ) {
                        Icon(Icons.Default.UploadFile, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.size(8.dp))
                        Text("Upload Recording")
                    }
                }
            }
        }
    }
}

@Composable
private fun PermissionDeniedContent(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    Column(
        modifier = modifier.padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(Icons.Default.Mic, contentDescription = null, modifier = Modifier.size(64.dp), tint = MaterialTheme.colorScheme.error)
        Spacer(modifier = Modifier.height(16.dp))
        Text("Microphone permission required", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            "VoiceBlogger needs microphone access to record your voice.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
        )
        Spacer(modifier = Modifier.height(24.dp))
        Button(onClick = {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", context.packageName, null)
            }
            context.startActivity(intent)
        }) {
            Text("Open Settings")
        }
    }
}
