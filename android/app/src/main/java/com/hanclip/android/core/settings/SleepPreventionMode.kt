package com.hanclip.android.core.settings

import android.content.Context

enum class SleepPreventionMode(
    val title: String,
    val chipTitle: String,
    val detail: String
) {
    AlwaysOn(
        title = "항상켜짐",
        chipTitle = "화면 계속",
        detail = "촬영, 편집, 저장 중에도 화면이 꺼지지 않게 계속 유지합니다."
    ),
    AlwaysOff(
        title = "끔",
        chipTitle = "화면 끔",
        detail = "시스템 화면 꺼짐 설정에 맞게 동작합니다."
    ),
    Automatic(
        title = "오토",
        chipTitle = "작업중 유지",
        detail = "AiShot 촬영, 사진/영상 가져오기, 완성본 만들기, 사진첩 저장 중에만 화면을 유지합니다."
    );

    fun next(): SleepPreventionMode {
        val modes = entries
        return modes[(ordinal + 1) % modes.size]
    }

    companion object {
        val Default: SleepPreventionMode = Automatic

        fun fromRawValue(rawValue: String?): SleepPreventionMode {
            return entries.firstOrNull { it.name == rawValue } ?: Default
        }
    }
}

object SleepPreventionStore {
    private const val PreferencesName = "hanclip_settings"
    private const val KeySleepPreventionMode = "hanClipSleepPreventionMode"

    fun load(context: Context): SleepPreventionMode {
        val preferences = context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
        return SleepPreventionMode.fromRawValue(preferences.getString(KeySleepPreventionMode, null))
    }

    fun save(context: Context, mode: SleepPreventionMode) {
        context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
            .edit()
            .putString(KeySleepPreventionMode, mode.name)
            .apply()
    }
}
