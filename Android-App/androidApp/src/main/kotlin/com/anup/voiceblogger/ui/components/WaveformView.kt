package com.anup.voiceblogger.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap

@Composable
fun WaveformView(
    amplitudeLevels: List<Float>,
    modifier: Modifier = Modifier,
    barColor: Color = Color(0xFF4FC3F7),
    barCount: Int = 30
) {
    Canvas(modifier = modifier.fillMaxSize()) {
        val width = size.width
        val height = size.height
        val centerY = height / 2f
        val barWidth = width / (barCount * 2f)
        val spacing = barWidth

        for (i in 0 until barCount) {
            val level = if (amplitudeLevels.isNotEmpty()) {
                amplitudeLevels.getOrElse(i) { 0f }.coerceIn(0f, 1f)
            } else 0.05f

            val barHeight = (height * 0.1f + height * 0.8f * level).coerceAtLeast(height * 0.05f)
            val x = i * (barWidth + spacing) + barWidth / 2f + spacing / 2f

            drawLine(
                color = barColor,
                start = Offset(x, centerY - barHeight / 2f),
                end = Offset(x, centerY + barHeight / 2f),
                strokeWidth = barWidth,
                cap = StrokeCap.Round
            )
        }
    }
}
