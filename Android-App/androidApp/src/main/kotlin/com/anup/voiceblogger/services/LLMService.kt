package com.anup.voiceblogger.services

import android.content.Context
import ai.onnxruntime.genai.Generator
import ai.onnxruntime.genai.GeneratorParams
import ai.onnxruntime.genai.Model
import ai.onnxruntime.genai.Tokenizer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import java.io.File

class LLMService(private val context: Context) {

    private val modelDir: String
        get() = File(context.filesDir, "models/llm/qwen2.5-2b").absolutePath

    fun isModelAvailable(): Boolean =
        File(modelDir, "genai_config.json").exists() &&
        File(modelDir, "model.onnx.data").exists()

    fun generateStream(prompt: String, maxTokens: Int): Flow<String> = flow {
        val model = Model(modelDir)
        val tokenizer = Tokenizer(model)
        val tokenizerStream = tokenizer.createStream()
        val sequences = tokenizer.encode(prompt)

        val params = GeneratorParams(model)
        params.setSearchOption("max_length", (maxTokens + 1024).toDouble())
        params.setSearchOption("temperature", 0.7)
        params.setSearchOption("top_p", 0.9)

        val generator = Generator(model, params)
        generator.appendTokenSequences(sequences)
        var prevLen = 0
        try {
            while (!generator.isDone()) {
                generator.generateNextToken()
                val tokens = generator.getSequence(0)
                for (i in prevLen until tokens.size) {
                    val text = tokenizerStream.decode(tokens[i])
                    if (text.isNotEmpty()) emit(text)
                }
                prevLen = tokens.size
            }
        } finally {
            generator.close()
            sequences.close()
            tokenizerStream.close()
            tokenizer.close()
            model.close()
        }
    }.flowOn(Dispatchers.IO)
}
