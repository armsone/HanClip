package com.hanclip.android.core.model

enum class WatermarkPosition(val gridColumn: Int, val gridRow: Int) {
    TopLeading(0, 0),
    TopQuarterLeading(1, 0),
    TopCenter(2, 0),
    TopQuarterTrailing(3, 0),
    TopTrailing(4, 0),
    UpperLeading(0, 1),
    UpperQuarterLeading(1, 1),
    UpperCenter(2, 1),
    UpperQuarterTrailing(3, 1),
    UpperTrailing(4, 1),
    MiddleLeading(0, 2),
    MiddleQuarterLeading(1, 2),
    Center(2, 2),
    MiddleQuarterTrailing(3, 2),
    MiddleTrailing(4, 2),
    LowerLeading(0, 3),
    LowerQuarterLeading(1, 3),
    LowerCenter(2, 3),
    LowerQuarterTrailing(3, 3),
    LowerTrailing(4, 3),
    BottomLeading(0, 4),
    BottomQuarterLeading(1, 4),
    BottomCenter(2, 4),
    BottomQuarterTrailing(3, 4),
    BottomTrailing(4, 4);

    val horizontalFraction: Double
        get() = gridColumn / 4.0

    val verticalFractionFromTop: Double
        get() = gridRow / 4.0
}

enum class WatermarkFontSize(val title: String, val pointSize: Int, val multiplier: Double) {
    Small("작게", 11, 0.8),
    Normal("기본", 14, 1.0),
    Large("크게", 21, 1.5),
    ExtraLarge("더크게", 26, 26.0 / 14.0)
}

enum class WatermarkLineSpacing(val title: String, val scale: Double) {
    Tight("좁게", 0.8),
    Normal("보통", 1.0),
    Wide("넓게", 1.2);

    companion object {
        const val DefaultScale = 1.0
        const val Step = 0.2
        const val MinimumScale = 0.5
        const val MaximumScale = 2.0

        fun normalize(scale: Double): Double = scale.coerceIn(MinimumScale, MaximumScale)
    }
}

enum class CopyrightIconColorMode(val title: String) {
    Original("기본"),
    Gray("회색"),
    Tint("지정색");

    companion object {
        fun fromStoredValue(value: String?): CopyrightIconColorMode {
            return when (value?.lowercase()) {
                "gray" -> Gray
                "tint", "overlay" -> Tint
                else -> Original
            }
        }
    }
}

enum class WatermarkPlatform(val title: String, val mark: String) {
    HanClip("한클립", "▶"),
    Instagram("인스타그램", "◎"),
    Facebook("페이스북", "f"),
    YouTube("유튜브", "▶"),
    Blog("블로그", "blog"),
    KakaoTalk("카카오톡", "TALK"),
    X("엑스", "𝕏"),
    Phone("전화번호", "☎"),
    Homepage("홈페이지", "◎"),
    Custom("직접입력", "▧");

    val storedValue: String
        get() = when (this) {
            HanClip -> "hanclip"
            Instagram -> "instagram"
            Facebook -> "facebook"
            YouTube -> "youtube"
            Blog -> "blog"
            KakaoTalk -> "kakaoTalk"
            X -> "x"
            Phone -> "phone"
            Homepage -> "homepage"
            Custom -> "custom"
        }

    companion object {
        fun fromStoredValue(value: String?): WatermarkPlatform {
            return entries.firstOrNull { it.storedValue == value }
                ?: if (value == "other") Custom else HanClip
        }
    }
}

data class WatermarkSettings(
    val isEnabled: Boolean = false,
    val logoEnabled: Boolean = false,
    val address: String = "",
    val platform: WatermarkPlatform = WatermarkPlatform.HanClip,
    val text: String = "오늘의 스윙\nHanClip",
    val position: WatermarkPosition = WatermarkPosition.TopLeading,
    val fontName: String = "pretendard",
    val textColorHex: String = "#FFFFFF",
    val shadowEnabled: Boolean = true,
    val shadowOpacity: Double = 0.2,
    val shadowColorHex: String = "#000000",
    val lineSpacing: WatermarkLineSpacing = WatermarkLineSpacing.Normal,
    val lineSpacingScale: Double = WatermarkLineSpacing.DefaultScale,
    val fontSize: WatermarkFontSize = WatermarkFontSize.Large,
    val logoColorHex: String = "#007644",
    val logoShadowColorHex: String = "#29AB87",
    val logoShadowOpacity: Double = 0.5,
    val copyrightPosition: WatermarkPosition = WatermarkPosition.BottomTrailing,
    val copyrightIconColorMode: CopyrightIconColorMode = CopyrightIconColorMode.Original,
    val copyrightIconColorHex: String = "#007644",
    val customCopyrightIconPath: String = ""
) {
    val shouldRenderText: Boolean
        get() = isEnabled && text.isNotBlank()

    val shouldRender: Boolean
        get() = logoEnabled || shouldRenderText

    val effectiveLogoColorHex: String
        get() = when (copyrightIconColorMode) {
            CopyrightIconColorMode.Original -> logoColorHex
            CopyrightIconColorMode.Gray -> "#8A8A8A"
            CopyrightIconColorMode.Tint -> copyrightIconColorHex
        }

    val displayCopyrightText: String
        get() = address.trim().ifBlank { platform.title }
}
