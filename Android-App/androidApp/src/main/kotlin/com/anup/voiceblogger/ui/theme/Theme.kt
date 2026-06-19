package com.anup.voiceblogger.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DarkColorScheme = darkColorScheme(
    primary = Color(0xFF4FC3F7),
    onPrimary = Color(0xFF003544),
    primaryContainer = Color(0xFF00516A),
    onPrimaryContainer = Color(0xFFB9EAFF),
    secondary = Color(0xFFB1CBB8),
    onSecondary = Color(0xFF1D352A),
    background = Color(0xFF191C1E),
    onBackground = Color(0xFFE1E2E4),
    surface = Color(0xFF191C1E),
    onSurface = Color(0xFFE1E2E4),
    surfaceVariant = Color(0xFF41484D),
    onSurfaceVariant = Color(0xFFC0C8CE),
)

private val LightColorScheme = lightColorScheme(
    primary = Color(0xFF006782),
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFB9EAFF),
    onPrimaryContainer = Color(0xFF001F28),
    secondary = Color(0xFF4C6358),
    onSecondary = Color(0xFFFFFFFF),
    background = Color(0xFFFBFCFE),
    onBackground = Color(0xFF191C1E),
    surface = Color(0xFFFBFCFE),
    onSurface = Color(0xFF191C1E),
    surfaceVariant = Color(0xFFDCE4E9),
    onSurfaceVariant = Color(0xFF41484D),
)

@Composable
fun VoiceBloggerTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme

    MaterialTheme(
        colorScheme = colorScheme,
        content = content
    )
}
