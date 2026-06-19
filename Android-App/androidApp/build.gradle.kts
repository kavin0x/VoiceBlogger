import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.net.URI

plugins {
    alias(libs.plugins.androidApplication)
    alias(libs.plugins.composeMultiplatform)
    alias(libs.plugins.composeCompiler)
    id("org.jetbrains.kotlin.plugin.serialization") version "2.4.0"
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_11
    }
}

// Download the ORT GenAI Android AAR from GitHub releases if not already present
val ortGenaiAarVersion = "0.14.0"
val ortGenaiAarFile = layout.projectDirectory.file("libs/onnxruntime-genai-android-$ortGenaiAarVersion.aar")

val downloadOrtGenaiAar by tasks.registering {
    // Capture as plain strings so configuration cache can serialize them
    val aarPath = ortGenaiAarFile.asFile.absolutePath
    val aarUrl = "https://github.com/microsoft/onnxruntime-genai/releases/download/" +
        "v$ortGenaiAarVersion/onnxruntime-genai-android-$ortGenaiAarVersion.aar"
    outputs.file(ortGenaiAarFile)
    doFirst {
        val f = File(aarPath)
        if (!f.exists()) {
            f.parentFile.mkdirs()
            println("Downloading ORT GenAI AAR $ortGenaiAarVersion...")
            URI(aarUrl).toURL().openStream().use { input: InputStream ->
                f.outputStream().use { output: OutputStream -> input.copyTo(output) }
            }
            println("ORT GenAI AAR downloaded to $aarPath")
        }
    }
}

tasks.named("preBuild") { dependsOn(downloadOrtGenaiAar) }

dependencies {
    implementation(projects.shared)

    implementation(libs.androidx.activity.compose)

    implementation(libs.compose.uiToolingPreview)
    debugImplementation(libs.compose.uiTooling)

    // Compose dependencies needed directly in androidApp
    implementation(libs.compose.runtime)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.ui)
    implementation(libs.compose.material.icons.extended)
    implementation(libs.androidx.lifecycle.viewmodelCompose)
    implementation(libs.androidx.lifecycle.runtimeCompose)
    implementation(libs.androidx.core.ktx)

    // AI libraries
    implementation(libs.sherpa.onnx)
    // ORT GenAI AAR (downloaded from GitHub releases by downloadOrtGenaiAar task)
    implementation(files("libs/onnxruntime-genai-android-$ortGenaiAarVersion.aar"))

    // Markdown rendering
    implementation(libs.markwon.core)

    // JSON serialization
    implementation(libs.kotlinx.serialization.json)
}

android {
    namespace = "com.anup.voiceblogger"
    compileSdk = libs.versions.android.compileSdk.get().toInt()
    buildToolsVersion = "36.1.0"

    defaultConfig {
        applicationId = "com.anup.voiceblogger"
        minSdk = libs.versions.android.minSdk.get().toInt()
        targetSdk = libs.versions.android.targetSdk.get().toInt()
        versionCode = 1
        versionName = "1.0"
    }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
        jniLibs {
            pickFirsts += "lib/*/libonnxruntime.so"
            pickFirsts += "lib/*/libonnxruntime4j_jni.so"
        }
    }
    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    buildFeatures {
        buildConfig = true
    }
}
