package com.hanclip.android.core.model

enum class MoviePreset(val routeValue: String, val title: String, val detail: String) {
    NewMovie("newMovie", "새 영화", "모든 것의 시작"),
    AiShot("aiShot", "AiShot", "스마트한 레코딩"),
    Travel("travel", "여행 영화", "여행을 추억으로"),
    Golf("golf", "골프 영화", "공도 넣고 기억도 넣고");

    companion object {
        fun fromRouteValue(value: String?): MoviePreset {
            return entries.firstOrNull { it.routeValue == value } ?: NewMovie
        }
    }
}
