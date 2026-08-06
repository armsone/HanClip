package com.hanclip.android.core.model

enum class BackgroundMusicSample(
    val id: String,
    val title: String,
    val detail: String,
    val rawResourceName: String
) {
    GolfLetsGo(
        id = "golf-lets-go",
        title = "골프치러 가자",
        detail = "골프 완성본 기본 샘플",
        rawResourceName = "golf_lets_go"
    ),
    TravelJoy(
        id = "travel-joy",
        title = "여행의 설렘",
        detail = "여행 완성본 기본 샘플",
        rawResourceName = "travel_joy"
    );

    companion object {
        fun fromId(id: String?): BackgroundMusicSample? {
            return entries.firstOrNull { it.id == id }
        }
    }
}
