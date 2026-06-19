package com.anup.voiceblogger.ui.components

import android.widget.TextView
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import io.noties.markwon.Markwon

@Composable
fun MarkdownView(
    markdown: String,
    modifier: Modifier = Modifier
) {
    AndroidView(
        modifier = modifier,
        factory = { context ->
            val markwon = Markwon.create(context)
            TextView(context).apply {
                textSize = 16f
            }.also { textView ->
                markwon.setMarkdown(textView, markdown)
            }
        },
        update = { textView ->
            val markwon = Markwon.create(textView.context)
            markwon.setMarkdown(textView, markdown)
        }
    )
}
