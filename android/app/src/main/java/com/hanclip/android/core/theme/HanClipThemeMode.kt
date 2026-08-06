package com.hanclip.android.core.theme

import android.content.Context
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

enum class HanClipThemeMode(
    val storageValue: String,
    val displayName: String,
    val palette: HanClipPalette
) {
    Automatic(
        "automatic",
        "자동 모드",
        HanClipPalette(
            primary = Color(0xFF072931),
            secondary = Color(0xFF007E81),
            background = Brush.verticalGradient(listOf(Color(0xFFF8FBFA), Color(0xFFE7F0EE))),
            text = Color(0xFF0F172A),
            subText = Color(0xFF52615D),
            panel = Color.White,
            chip = Color(0xFFE6F4F3),
            border = Color(0xFFD3E3DF)
        )
    ),
    Light(
        "light",
        "밝은 모드",
        HanClipPalette(
            primary = Color(0xFF0B7A4E),
            secondary = Color(0xFF29AB87),
            background = Brush.verticalGradient(listOf(Color(0xFFFAFCFA), Color(0xFFF4F7F5))),
            text = Color(0xFF14221A),
            subText = Color(0xFF46564C),
            panel = Color.White,
            chip = Color(0xFFEAF5F0),
            border = Color(0xFFD4DDD7)
        )
    ),
    Dark(
        "dark",
        "어두운 모드",
        HanClipPalette(
            primary = Color(0xFF67E8F9),
            secondary = Color(0xFF527387),
            background = Brush.verticalGradient(listOf(Color(0xFF0F172A), Color(0xFF111827))),
            text = Color(0xFFF8FAFC),
            subText = Color(0xFFC9D3DC),
            panel = Color(0xFF1F2937),
            chip = Color(0xFF233445),
            border = Color(0xFF3F5262)
        )
    ),
    BlossomGlow(
        "blossomGlow",
        "블라썸 글로우",
        HanClipPalette(
            primary = Color(0xFFB9486A),
            secondary = Color(0xFFF39B7D),
            background = Brush.verticalGradient(listOf(Color(0xFFFFF7F8), Color(0xFFFFECE8))),
            text = Color(0xFF331B23),
            subText = Color(0xFF76515C),
            panel = Color.White,
            chip = Color(0xFFFFE6EA),
            border = Color(0xFFF4C8D0)
        )
    ),
    GrayscalePlay(
        "grayscalePlay",
        "그레이스케일",
        HanClipPalette(
            primary = Color(0xFF242424),
            secondary = Color(0xFF8B8B8B),
            background = Brush.verticalGradient(listOf(Color(0xFFFAFAFA), Color(0xFFEDEDED))),
            text = Color(0xFF171717),
            subText = Color(0xFF5F5F5F),
            panel = Color.White,
            chip = Color(0xFFE9E9E9),
            border = Color(0xFFD2D2D2)
        )
    ),
    PixelPop(
        "pixelPop",
        "픽셀 팝",
        HanClipPalette(
            primary = Color(0xFF2652FF),
            secondary = Color(0xFFDC2F65),
            background = Brush.verticalGradient(listOf(Color(0xFFF9FBFF), Color(0xFFE8EFFF))),
            text = Color(0xFF0F1630),
            subText = Color(0xFF56617F),
            panel = Color.White,
            chip = Color(0xFFE6EAFF),
            border = Color(0xFFC9D3FF)
        )
    );

    companion object {
        val visibleModes = entries

        fun fromStoredValue(value: String?): HanClipThemeMode {
            return entries.firstOrNull { it.storageValue == value }
                ?: when (value) {
                    "readableComfort" -> Light
                    "rosyBrown", "electricCobalt" -> Automatic
                    else -> Automatic
                }
        }
    }
}

data class HanClipPalette(
    val primary: Color,
    val secondary: Color,
    val background: Brush,
    val text: Color,
    val subText: Color,
    val panel: Color,
    val chip: Color,
    val border: Color
)

object HanClipThemeStore {
    private const val PreferencesName = "hanclip_home_theme_preferences"
    private const val ThemeModeKey = "hanClipThemeMode"

    fun load(context: Context): HanClipThemeMode {
        val raw = context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
            .getString(ThemeModeKey, null)
        return HanClipThemeMode.fromStoredValue(raw)
    }

    fun save(context: Context, mode: HanClipThemeMode) {
        context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
            .edit()
            .putString(ThemeModeKey, mode.storageValue)
            .apply()
    }
}
