package com.hanclip.android.core.model

enum class OutputQualityPreset(
    val title: String,
    val detail: String,
    val frameRate: Int
) {
    Standard("표준", "30fps · 용량 균형", 30),
    Smooth("부드럽게", "60fps · 움직임 선명", 60);

    val displayTitle: String
        get() = "$title $detail"

    val chipTitle: String
        get() = "$title $detail"

    companion object {
        const val ExportFormatTitle = "MP4"
        const val CodecTitle = "H.264 영상 · AAC 음성"
        const val ExportFormatDetail = "$ExportFormatTitle · $CodecTitle"
        const val GallerySaveDetail = "$ExportFormatDetail · HanClip 앨범 저장"
    }
}
