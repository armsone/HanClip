package com.hanclip.android.core.model

enum class OutputQualityPreset(
    val title: String,
    val detail: String,
    val frameRate: Int
) {
    Standard("표준", "30fps", 30),
    Smooth("부드럽게", "60fps", 60);

    val displayTitle: String
        get() = "$title $detail"
}
