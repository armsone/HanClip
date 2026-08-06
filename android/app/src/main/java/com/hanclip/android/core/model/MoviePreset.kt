package com.hanclip.android.core.model

enum class MoviePreset(val routeValue: String, val title: String, val detail: String) {
    NewMovie("newMovie", "새 영화", "사진/영상 한 번에 고르기"),
    AiShot("aiShot", "AiShot", "스윙 순간 자동 촬영"),
    Travel("travel", "여행 영화", "여행 사진을 짧은 영화로"),
    Golf("golf", "골프 영화", "타격점 기준 자동 클립");

    companion object {
        fun fromRouteValue(value: String?): MoviePreset {
            return entries.firstOrNull { it.routeValue == value } ?: NewMovie
        }
    }
}
