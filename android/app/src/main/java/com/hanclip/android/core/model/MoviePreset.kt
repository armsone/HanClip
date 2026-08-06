package com.hanclip.android.core.model

enum class MoviePreset(val routeValue: String, val title: String, val detail: String) {
    NewMovie("newMovie", "새 완성본", "사진/영상 한 번에 선택"),
    AiShot("aiShot", "AiShot", "스윙 순간 자동 촬영"),
    Travel("travel", "여행 완성본", "여행 사진을 짧게 연결"),
    Golf("golf", "골프 완성본", "타격점 중심 자동 컷");

    companion object {
        fun fromRouteValue(value: String?): MoviePreset {
            return entries.firstOrNull { it.routeValue == value } ?: NewMovie
        }
    }
}
