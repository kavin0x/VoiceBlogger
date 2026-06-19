package com.anup.voiceblogger

interface Platform {
    val name: String
}

expect fun getPlatform(): Platform