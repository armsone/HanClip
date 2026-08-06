package com.hanclip.android.core.navigation

import android.net.Uri

enum class HanClipQuickAction {
    Open,
    AiShot,
    Photo,
    Calendar,
    Files,
    Search;

    companion object {
        fun fromUri(uri: Uri?): HanClipQuickAction? {
            if (uri?.scheme != "hanclip") return null
            return when (uri.host ?: uri.pathSegments.firstOrNull()) {
                "open" -> Open
                "aishot" -> AiShot
                "photo" -> Photo
                "calendar" -> Calendar
                "files" -> Files
                "search" -> Search
                else -> null
            }
        }
    }
}
