package com.anup.voiceblogger

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.anup.voiceblogger.data.BlogPost
import com.anup.voiceblogger.state.AppStage
import com.anup.voiceblogger.state.AppStateViewModel
import com.anup.voiceblogger.ui.screens.AboutScreen
import com.anup.voiceblogger.ui.screens.BlogScreen
import com.anup.voiceblogger.ui.screens.HistoryScreen
import com.anup.voiceblogger.ui.screens.InstagramScreen
import com.anup.voiceblogger.ui.screens.LinkedInScreen
import com.anup.voiceblogger.ui.screens.ModelDownloadScreen
import com.anup.voiceblogger.ui.screens.OnboardingScreen
import com.anup.voiceblogger.ui.screens.RecordingScreen
import com.anup.voiceblogger.ui.screens.TranscriptionScreen
import com.anup.voiceblogger.ui.theme.VoiceBloggerTheme

class MainActivity : ComponentActivity() {

    private val appState: AppStateViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)

        val app = application as VoiceBloggerApplication

        // Determine initial stage
        val modelsReady = app.modelDownloadManager.status.value.allModelsReady
        if (!modelsReady) {
            appState.navigateTo(AppStage.ModelDownload)
        } else {
            appState.navigateTo(AppStage.Recording)
        }

        setContent {
            VoiceBloggerTheme {
                VoiceBloggerApp(app, appState)
            }
        }
    }
}

@Composable
fun VoiceBloggerApp(app: VoiceBloggerApplication, appState: AppStateViewModel) {
    val stage by appState.stage.collectAsState()

    when (val currentStage = stage) {
        is AppStage.ModelDownload -> ModelDownloadScreen(
            downloadManager = app.modelDownloadManager,
            onComplete = { appState.navigateTo(AppStage.Onboarding) }
        )

        is AppStage.Onboarding -> OnboardingScreen(
            onComplete = { appState.navigateTo(AppStage.Recording) }
        )

        is AppStage.Recording -> RecordingScreen(
            recorder = app.audioRecorderService,
            repository = app.repository,
            onStartTranscription = { post -> appState.goToTranscribing(post) },
            onOpenHistory = { appState.goToHistory() },
            onOpenAbout = { appState.navigateTo(AppStage.About) },
            onResetModels = {
                app.modelDownloadManager.resetModels()
                appState.navigateTo(AppStage.ModelDownload)
            }
        )

        is AppStage.Transcribing -> TranscriptionScreen(
            post = currentStage.post,
            transcriptionService = app.transcriptionService,
            repository = app.repository,
            onBack = { appState.goToRecording() },
            onGenerateBlog = { updatedPost ->
                appState.goToViewingBlog(updatedPost)
            }
        )

        is AppStage.PreparingBlog -> {
            LaunchedEffect(currentStage.postId) {
                val post = app.repository.getPost(currentStage.postId)
                if (post != null) {
                    appState.goToViewingBlog(post)
                } else {
                    appState.goToRecording()
                }
            }
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        }

        is AppStage.GeneratingBlog -> BlogScreen(
            post = currentStage.post,
            llmService = app.llmService,
            repository = app.repository,
            onNewRecording = { appState.goToRecording() },
            onOpenInstagram = { post -> appState.goToViewingInstagram(post) },
            onOpenLinkedIn = { post -> appState.goToViewingLinkedIn(post) },
            onOpenHistory = { appState.goToHistory() }
        )

        is AppStage.ViewingBlog -> BlogScreen(
            post = currentStage.post,
            llmService = app.llmService,
            repository = app.repository,
            onNewRecording = { appState.goToRecording() },
            onOpenInstagram = { post -> appState.goToViewingInstagram(post) },
            onOpenLinkedIn = { post -> appState.goToViewingLinkedIn(post) },
            onOpenHistory = { appState.goToHistory() }
        )

        is AppStage.ViewingInstagram -> InstagramScreen(
            post = currentStage.post,
            llmService = app.llmService,
            repository = app.repository,
            onBack = { appState.goToViewingBlog(currentStage.post) }
        )

        is AppStage.ViewingLinkedIn -> LinkedInScreen(
            post = currentStage.post,
            llmService = app.llmService,
            repository = app.repository,
            onBack = { appState.goToViewingBlog(currentStage.post) }
        )

        is AppStage.History -> HistoryScreen(
            repository = app.repository,
            onBack = { appState.navigateTo(AppStage.Recording) },
            onOpenPost = { post ->
                if (post.blogContent.isNotBlank()) {
                    appState.goToViewingBlog(post)
                } else {
                    appState.goToTranscribing(post)
                }
            }
        )

        is AppStage.About -> AboutScreen(
            onBack = { appState.navigateTo(AppStage.Recording) }
        )
    }
}
