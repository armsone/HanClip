package com.hanclip.android.core.model

import android.net.Uri
import java.util.UUID
import kotlin.math.max
import kotlin.math.min

enum class ClipMediaKind {
    Photo,
    LivePhoto,
    Video
}

enum class LivePhotoMode(val title: String) {
    Still("사진"),
    Motion("Live")
}

enum class VideoSegmentMode(val title: String) {
    Single("단일"),
    Multiple("다중"),
    All("전체")
}

data class ClipItem(
    val id: String = UUID.randomUUID().toString(),
    val sourceUri: Uri,
    val thumbnailUri: Uri? = null,
    val durationSeconds: Double = 4.0,
    val photoDurationSeconds: Double = durationSeconds,
    val livePhotoDurationSeconds: Double? = null,
    val livePhotoStillUri: Uri? = null,
    val isLivePhoto: Boolean = false,
    val livePhotoMode: LivePhotoMode = LivePhotoMode.Still,
    val mediaKind: ClipMediaKind = if (isLivePhoto) ClipMediaKind.LivePhoto else ClipMediaKind.Photo,
    val sourceDurationSeconds: Double? = null,
    val trimStartSeconds: Double = 0.0,
    val audioWaveform: List<Double> = emptyList(),
    val audioPeakTimeSeconds: Double? = null,
    val audioPeakTimesSeconds: List<Double> = emptyList(),
    val videoSegmentMode: VideoSegmentMode = VideoSegmentMode.Single,
    val isVideoSegmentParent: Boolean = false,
    val videoSegmentParentId: String? = null,
    val photoSimilarityFingerprint: List<Int> = emptyList(),
    val sourceCreatedAtMillis: Long? = null,
    val similarPhotoGroupId: String? = null,
    val similarPhotoGroupIndex: Int = 0,
    val similarPhotoGroupCount: Int = 1,
    val isSimilarPhotoGroupRepresentative: Boolean = true,
    val sourceWidth: Int = 1,
    val sourceHeight: Int = 1
) {
    val trimEndSeconds: Double
        get() = min(sourceDurationSeconds ?: durationSeconds, trimStartSeconds + durationSeconds)

    val isVideoSegmentChild: Boolean
        get() = videoSegmentParentId != null

    val isSimilarPhotoGroupMember: Boolean
        get() = similarPhotoGroupId != null

    val isSimilarPhotoGroupParent: Boolean
        get() = similarPhotoGroupId != null && similarPhotoGroupCount > 1 && similarPhotoGroupIndex == 0

    val isSimilarPhotoGroupChild: Boolean
        get() = similarPhotoGroupId != null && similarPhotoGroupCount > 1 && similarPhotoGroupIndex > 0

    val isHiddenSimilarPhotoGroupMember: Boolean
        get() = similarPhotoGroupId != null && !isSimilarPhotoGroupRepresentative

    val isRenderableClip: Boolean
        get() = !isVideoSegmentParent && !isHiddenSimilarPhotoGroupMember

    val sourceAspectRatio: Double
        get() = sourceWidth.toDouble() / max(1, sourceHeight).toDouble()
}
