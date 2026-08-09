package com.hanclip.android.core.media

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color as AndroidColor
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.Typeface
import android.media.MediaExtractor
import android.media.MediaMuxer
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaCodec
import android.net.Uri
import android.text.SpannableString
import android.text.Spanned
import android.text.TextPaint
import android.text.style.CharacterStyle
import android.text.style.MetricAffectingSpan
import android.text.style.AbsoluteSizeSpan
import android.text.style.ForegroundColorSpan
import android.text.style.LineHeightSpan
import android.text.style.StyleSpan
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.container.MdtaMetadataEntry
import androidx.media3.container.Mp4TimestampData
import androidx.media3.container.Mp4LocationData
import androidx.media3.common.audio.DefaultGainProvider
import androidx.media3.common.audio.GainProcessor
import androidx.media3.common.util.UnstableApi
import com.hanclip.android.core.model.ClipItem
import com.hanclip.android.core.model.ClipMediaKind
import com.hanclip.android.core.model.LivePhotoMode
import com.hanclip.android.core.model.WatermarkSettings
import com.hanclip.android.core.model.CopyrightIconColorMode
import com.hanclip.android.core.model.drawableResId
import com.hanclip.android.core.project.ImportedFontStore
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.Presentation
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.effect.TextOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.InAppMp4Muxer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import java.util.Collections
import java.nio.ByteBuffer
import java.io.File
import java.time.Instant
import org.json.JSONObject
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.abs

data class VideoExportRequest(
    val clips: List<ClipItem>,
    val renderWidth: Int,
    val renderHeight: Int,
    val frameRate: Int = 30,
    val watermarkSettings: WatermarkSettings = WatermarkSettings(),
    val backgroundMusicUri: Uri? = null,
    val backgroundMusicVolume: Double = 0.35,
    val originalAudioVolume: Double = 1.0,
    val backgroundMusicLoopsToFillVideo: Boolean = true,
    val backgroundMusicFadeInEnabled: Boolean = true,
    val backgroundMusicFadeOutEnabled: Boolean = true,
    val madeAtMillis: Long = System.currentTimeMillis(),
    val shootingStartAtMillis: Long? = null,
    val shootingEndAtMillis: Long? = null,
    val locationName: String? = null,
    val routeLocationNames: List<String> = emptyList(),
    val latitude: Double? = null,
    val longitude: Double? = null,
    val embedHanClipMetadata: Boolean = true
)

interface VideoExportService {
    suspend fun export(request: VideoExportRequest, onProgress: (Double) -> Unit): Uri
}

@androidx.annotation.OptIn(UnstableApi::class)
class Media3TransformerExportService(
    private val context: Context
) : VideoExportService {
    private val maxExportCacheFiles = 20

    override suspend fun export(request: VideoExportRequest, onProgress: (Double) -> Unit): Uri {
        require(request.clips.isNotEmpty()) { "내보낼 클립이 없습니다." }
        val outputDirectory = File(context.cacheDir, "exports").apply {
            mkdirs()
        }
        pruneExportCache(outputDirectory)
        val outputFile = File(outputDirectory, "hanclip-preview-${System.currentTimeMillis()}.mp4")
        if (outputFile.exists()) outputFile.delete()
        val endingInfoFile = EndingInfoCardRenderer.renderToFile(
            context = context,
            clips = request.clips,
            width = request.renderWidth,
            height = request.renderHeight,
            settings = request.watermarkSettings
        )
        val effectiveClips = if (endingInfoFile != null) {
            request.clips + ClipItem(
                sourceUri = Uri.fromFile(endingInfoFile),
                thumbnailUri = Uri.fromFile(endingInfoFile),
                durationSeconds = request.watermarkSettings.normalizedEndingInfoCardDuration,
                photoDurationSeconds = request.watermarkSettings.normalizedEndingInfoCardDuration,
                mediaKind = ClipMediaKind.Photo,
                sourceCreatedAtMillis = request.shootingEndAtMillis,
                sourceWidth = request.renderWidth,
                sourceHeight = request.renderHeight
            )
        } else {
            request.clips
        }

        effectiveClips.singleOrNull()
            ?.takeIf { it.mediaKind == ClipMediaKind.Video }
            ?.takeIf { canUseMuxerFastPath(it, request) }
            ?.let { clip ->
                return trimSingleVideoClip(clip, outputFile, onProgress)
            }

        val effects = effectsForRequest(request)
        val editedItems = effectiveClips.map { clip ->
            val builder = EditedMediaItem.Builder(mediaItemForClip(clip))
                .setRemoveAudio(clip.mediaKind != ClipMediaKind.Video)
                .setRemoveVideo(false)
                .setFrameRate(request.frameRate)
            builder.setEffects(effects)
            builder.build()
        }
        val videoSequence = EditedMediaItemSequence.Builder(editedItems)
            .experimentalSetForceVideoTrack(true)
            .build()
        val sequences = mutableListOf(videoSequence)
        request.backgroundMusicUri?.let { musicUri ->
            sequences += EditedMediaItemSequence.Builder(
                EditedMediaItem.Builder(MediaItem.fromUri(musicUri))
                    .setRemoveVideo(true)
                    .setRemoveAudio(false)
                    .setEffects(Effects(audioProcessorsForMusic(request), Collections.emptyList()))
                    .build()
            )
                .setIsLooping(request.backgroundMusicLoopsToFillVideo)
                .experimentalSetForceAudioTrack(true)
                .build()
        }
        val composition = Composition.Builder(sequences)
            .experimentalSetForceAudioTrack(false)
            .build()

        return suspendCancellableCoroutine { continuation ->
            var progressJob: Job? = null
            val transformer = Transformer.Builder(context)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setMuxerFactory(hanClipMuxerFactory(request))
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(
                        composition: Composition,
                        exportResult: ExportResult
                    ) {
                        progressJob?.cancel()
                        runCatching { endingInfoFile?.delete() }
                        onProgress(1.0)
                        if (continuation.isActive) {
                            if (outputFile.length() > 0L) {
                                continuation.resume(Uri.fromFile(outputFile))
                            } else {
                                continuation.resumeWithException(
                                    IllegalStateException("완성된 영상 파일이 비어 있습니다.")
                                )
                            }
                        }
                    }

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exportException: ExportException
                    ) {
                        progressJob?.cancel()
                        runCatching { endingInfoFile?.delete() }
                        runCatching { outputFile.delete() }
                        if (continuation.isActive) {
                            continuation.resumeWithException(exportException)
                        }
                    }
                })
                .build()

            continuation.invokeOnCancellation {
                progressJob?.cancel()
                transformer.cancel()
                runCatching { endingInfoFile?.delete() }
            }
            onProgress(0.05)
            transformer.start(composition, outputFile.absolutePath)
            progressJob = pollTransformerProgress(transformer, onProgress)
        }
    }

    private fun hanClipMuxerFactory(request: VideoExportRequest): InAppMp4Muxer.Factory {
        val metadataJson = JSONObject()
            .put("marker", HanClipMetadataKey)
            .put("schemaVersion", 1)
            .put("madeAtMillis", request.madeAtMillis)
            .put("shootingStartAtMillis", request.shootingStartAtMillis ?: JSONObject.NULL)
            .put("shootingEndAtMillis", request.shootingEndAtMillis ?: JSONObject.NULL)
            .put("locationName", request.locationName ?: JSONObject.NULL)
            .put("routeLocationNames", request.routeLocationNames)
            .put("latitude", request.latitude ?: JSONObject.NULL)
            .put("longitude", request.longitude ?: JSONObject.NULL)
            .toString()
        val iosCompatibleMetadata = JSONObject()
            .put(
                "shootingStartAt",
                request.shootingStartAtMillis?.let { Instant.ofEpochMilli(it).toString() }
                    ?: JSONObject.NULL
            )
            .put(
                "shootingEndAt",
                request.shootingEndAtMillis?.let { Instant.ofEpochMilli(it).toString() }
                    ?: JSONObject.NULL
            )
            .put("latitude", request.latitude ?: JSONObject.NULL)
            .put("longitude", request.longitude ?: JSONObject.NULL)
            .put("locationName", request.locationName ?: JSONObject.NULL)
            .put("routeLocationNames", request.routeLocationNames)
            .toString()
        return InAppMp4Muxer.Factory { entries ->
            entries.removeAll { entry ->
                entry is MdtaMetadataEntry &&
                    (entry.key == HanClipMetadataKey || entry.key == QuickTimeDescriptionKey)
            }
            entries += MdtaMetadataEntry(
                HanClipMetadataKey,
                metadataJson.toByteArray(Charsets.UTF_8),
                MdtaMetadataEntry.TYPE_INDICATOR_STRING
            )
            entries += MdtaMetadataEntry(
                QuickTimeDescriptionKey,
                (HanClipPayloadPrefix + iosCompatibleMetadata).toByteArray(Charsets.UTF_8),
                MdtaMetadataEntry.TYPE_INDICATOR_STRING
            )
            val unixSeconds = request.madeAtMillis / 1_000L
            val mp4Seconds = Mp4TimestampData.unixTimeToMp4TimeSeconds(unixSeconds)
            entries.removeAll { entry -> entry is Mp4TimestampData }
            entries += Mp4TimestampData(mp4Seconds, mp4Seconds)
            if (request.latitude != null && request.longitude != null) {
                entries.removeAll { entry -> entry is Mp4LocationData }
                entries += Mp4LocationData(
                    request.latitude.toFloat(),
                    request.longitude.toFloat()
                )
            }
        }
    }

    private fun pollTransformerProgress(
        transformer: Transformer,
        onProgress: (Double) -> Unit
    ): Job {
        val progressHolder = ProgressHolder()
        return CoroutineScope(Dispatchers.Main.immediate).launch {
            var lastProgress = 5
            while (true) {
                val state = transformer.getProgress(progressHolder)
                if (state == Transformer.PROGRESS_STATE_AVAILABLE) {
                    val progress = progressHolder.progress.coerceIn(0, 99)
                    if (progress > lastProgress) {
                        lastProgress = progress
                        onProgress(progress / 100.0)
                    }
                }
                delay(250)
            }
        }
    }

    private fun pruneExportCache(directory: File) {
        val files = directory.listFiles()
            ?.filter { it.isFile && it.name.startsWith("hanclip-preview-") }
            ?.sortedByDescending { it.lastModified() }
            .orEmpty()
        files.drop(maxExportCacheFiles).forEach { file ->
            runCatching { file.delete() }
        }
    }

    private fun mediaItemForClip(clip: ClipItem): MediaItem {
        val usesMotion = clip.mediaKind == ClipMediaKind.LivePhoto &&
            clip.livePhotoMode == LivePhotoMode.Motion
        val builder = MediaItem.Builder()
            .setUri(
                if (clip.mediaKind == ClipMediaKind.LivePhoto && !usesMotion) {
                    clip.livePhotoStillUri ?: clip.thumbnailUri ?: clip.sourceUri
                } else {
                    clip.sourceUri
                }
            )

        if (clip.mediaKind == ClipMediaKind.Video || usesMotion) {
            val startMs = (clip.trimStartSeconds * 1000).toLong().coerceAtLeast(0)
            val endMs = ((clip.trimStartSeconds + clip.durationSeconds) * 1000).toLong()
                .coerceAtLeast(startMs + 100)
            builder.setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionMs(startMs)
                    .setEndPositionMs(endMs)
                    .build()
            )
        } else {
            builder.setImageDurationMs((clip.durationSeconds * 1000).toLong().coerceAtLeast(100))
        }

        return builder.build()
    }

    private fun canUseMuxerFastPath(clip: ClipItem, request: VideoExportRequest): Boolean {
        return !request.embedHanClipMetadata &&
            !request.watermarkSettings.shouldRender &&
            request.backgroundMusicUri == null &&
            isUnityVolume(request.originalAudioVolume) &&
            clip.sourceWidth == request.renderWidth &&
            clip.sourceHeight == request.renderHeight
    }

    private companion object {
        const val HanClipMetadataKey = "HANCLIP_METADATA"
        const val HanClipPayloadPrefix = "HANCLIP_METADATA:"
        const val QuickTimeDescriptionKey = "com.apple.quicktime.description"
    }

    private fun effectsForRequest(request: VideoExportRequest): Effects {
        val videoEffects = mutableListOf<Effect>(
            Presentation.createForWidthAndHeight(
                request.renderWidth,
                request.renderHeight,
                Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP
            )
        )
        val watermark = request.watermarkSettings
        if (!watermark.shouldRender) {
            return Effects(audioProcessorsForVolume(request.originalAudioVolume), videoEffects)
        }

        val overlays = buildList {
            if (watermark.shouldRenderText) {
                add(
                    textOverlay(
                        text = watermark.text.trim(),
                        colorHex = watermark.textColorHex,
                        shadowColorHex = watermark.shadowColorHex,
                        shadowOpacity = watermark.shadowOpacity,
                        shadowEnabled = watermark.shadowEnabled,
                        fontName = watermark.fontName,
                        pointSize = watermark.fontSize.pointSize,
                        lineSpacingScale = watermark.lineSpacingScale,
                        position = watermark.position
                    )
                )
            }
            if (watermark.logoEnabled) {
                add(copyrightBitmapOverlay(watermark, request.renderWidth))
            }
        }
        videoEffects += OverlayEffect(overlays)
        return Effects(audioProcessorsForVolume(request.originalAudioVolume), videoEffects)
    }

    private fun audioProcessorsForVolume(volume: Double): List<GainProcessor> {
        val safeVolume = volume.coerceIn(0.0, 1.5)
        if (isUnityVolume(safeVolume)) return Collections.emptyList()
        return listOf(
            GainProcessor(
                DefaultGainProvider.Builder(safeVolume.toFloat()).build()
            )
        )
    }

    private fun audioProcessorsForMusic(request: VideoExportRequest): List<GainProcessor> {
        val processors = audioProcessorsForVolume(request.backgroundMusicVolume).toMutableList()
        val totalDurationUs = (request.clips.sumOf { it.durationSeconds } * 1_000_000.0)
            .toLong()
            .coerceAtLeast(1L)
        val fadeProvider = DefaultGainProvider.Builder(1f)
        var hasFade = false
        if (request.backgroundMusicFadeInEnabled) {
            val durationUs = minOf(300_000L, totalDurationUs / 2).coerceAtLeast(1L)
            fadeProvider.addFadeAt(0L, durationUs, DefaultGainProvider.FADE_IN_LINEAR)
            hasFade = true
        }
        if (request.backgroundMusicFadeOutEnabled) {
            val durationUs = minOf(1_000_000L, totalDurationUs / 2).coerceAtLeast(1L)
            fadeProvider.addFadeAt(
                totalDurationUs - durationUs,
                durationUs,
                DefaultGainProvider.FADE_OUT_LINEAR
            )
            hasFade = true
        }
        if (hasFade) processors += GainProcessor(fadeProvider.build())
        return processors
    }

    private fun isUnityVolume(volume: Double): Boolean {
        return abs(volume - 1.0) < 0.001
    }

    private fun copyrightBitmapOverlay(
        watermark: WatermarkSettings,
        renderWidth: Int
    ): BitmapOverlay {
        val iconSource = watermark.customCopyrightIconPath
            .takeIf { watermark.platform == com.hanclip.android.core.model.WatermarkPlatform.Custom }
            ?.let(BitmapFactory::decodeFile)
            ?: BitmapFactory.decodeResource(context.resources, watermark.platform.drawableResId)
        val iconSize = (renderWidth * 0.036f).toInt().coerceIn(32, 96)
        val textSize = (renderWidth * 0.018f).coerceIn(18f, 44f)
        val gap = (iconSize * 0.18f).toInt().coerceAtLeast(5)
        val padding = (iconSize * 0.18f).toInt().coerceAtLeast(6)
        val label = if (watermark.platform == com.hanclip.android.core.model.WatermarkPlatform.HanClip) {
            "HanClip"
        } else {
            watermark.displayCopyrightText
        }
        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = Typeface.create(typefaceForWatermark("pretendard"), Typeface.BOLD)
            this.textSize = textSize
            color = runCatching { AndroidColor.parseColor(watermark.effectiveLogoColorHex) }
                .getOrElse { AndroidColor.WHITE }
            if (watermark.logoShadowOpacity > 0.0) {
                setShadowLayer(
                    textSize * 0.13f,
                    textSize * 0.05f,
                    textSize * 0.06f,
                    shadowColorWithOpacity(watermark.logoShadowColorHex, watermark.logoShadowOpacity)
                )
            }
        }
        val textWidth = textPaint.measureText(label).toInt().coerceAtLeast(1)
        val fontMetrics = textPaint.fontMetrics
        val textHeight = (fontMetrics.descent - fontMetrics.ascent).toInt().coerceAtLeast(1)
        val bitmapWidth = padding * 2 + iconSize + gap + textWidth
        val bitmapHeight = padding * 2 + maxOf(iconSize, textHeight)
        val bitmap = Bitmap.createBitmap(bitmapWidth, bitmapHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val iconTop = (bitmapHeight - iconSize) / 2
        iconSource?.let { source ->
            val iconPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
                if (watermark.copyrightIconColorMode != CopyrightIconColorMode.Original) {
                    colorFilter = PorterDuffColorFilter(textPaint.color, PorterDuff.Mode.SRC_IN)
                }
                if (watermark.logoShadowOpacity > 0.0) {
                    setShadowLayer(
                        iconSize * 0.08f,
                        iconSize * 0.03f,
                        iconSize * 0.04f,
                        shadowColorWithOpacity(watermark.logoShadowColorHex, watermark.logoShadowOpacity)
                    )
                }
            }
            canvas.drawBitmap(
                source,
                null,
                android.graphics.Rect(padding, iconTop, padding + iconSize, iconTop + iconSize),
                iconPaint
            )
        }
        val textBaseline = (bitmapHeight - (fontMetrics.descent + fontMetrics.ascent)) / 2f
        canvas.drawText(label, (padding + iconSize + gap).toFloat(), textBaseline, textPaint)
        val anchorX = watermarkAnchorX(watermark.copyrightPosition.horizontalFraction)
        val anchorY = watermarkAnchorY(watermark.copyrightPosition.verticalFractionFromTop)
        val settings = StaticOverlaySettings.Builder()
            .setBackgroundFrameAnchor(anchorX, anchorY)
            .setOverlayFrameAnchor(anchorX, anchorY)
            .setScale(1f, 1f)
            .build()
        return BitmapOverlay.createStaticBitmapOverlay(bitmap, settings)
    }

    private fun textOverlay(
        text: String,
        colorHex: String,
        shadowColorHex: String,
        shadowOpacity: Double,
        shadowEnabled: Boolean,
        fontName: String,
        pointSize: Int,
        lineSpacingScale: Double,
        position: com.hanclip.android.core.model.WatermarkPosition
    ): TextOverlay {
        val styledText = SpannableString(text).apply {
            val textColor = runCatching { AndroidColor.parseColor(colorHex) }
                .getOrElse { AndroidColor.WHITE }
            setSpan(ForegroundColorSpan(textColor), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            setSpan(HanClipTypefaceSpan(typefaceForWatermark(fontName)), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            setSpan(StyleSpan(Typeface.BOLD), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            setSpan(
                AbsoluteSizeSpan(pointSize, true),
                0,
                length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            setSpan(
                FixedLineHeightSpan((pointSize * lineSpacingScale.coerceIn(0.5, 2.0) * 1.35).toInt()),
                0,
                length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            if (shadowEnabled) {
                val shadowColor = shadowColorWithOpacity(shadowColorHex, shadowOpacity)
                setSpan(
                    ShadowLayerSpan(
                        radius = 4f,
                        dx = 1.6f,
                        dy = 1.8f,
                        color = shadowColor
                    ),
                    0,
                    length,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }
        }
        val overlayAnchorX = watermarkAnchorX(position.horizontalFraction)
        val overlayAnchorY = watermarkAnchorY(position.verticalFractionFromTop)
        val settings = StaticOverlaySettings.Builder()
            .setBackgroundFrameAnchor(overlayAnchorX, overlayAnchorY)
            .setOverlayFrameAnchor(overlayAnchorX, overlayAnchorY)
            .setScale(1f, 1f)
            .build()
        return TextOverlay.createStaticTextOverlay(styledText, settings)
    }

    private fun watermarkAnchorX(fraction: Double): Float {
        val paddedFraction = 0.08 + fraction.coerceIn(0.0, 1.0) * 0.84
        return (paddedFraction * 2.0 - 1.0).toFloat()
    }

    private fun watermarkAnchorY(fractionFromTop: Double): Float {
        val paddedFractionFromTop = 0.08 + fractionFromTop.coerceIn(0.0, 1.0) * 0.84
        return (1.0 - paddedFractionFromTop * 2.0).toFloat()
    }

    private fun shadowColorWithOpacity(colorHex: String, opacity: Double): Int {
        val baseColor = runCatching { AndroidColor.parseColor(colorHex) }
            .getOrElse { AndroidColor.BLACK }
        val alpha = (opacity.coerceIn(0.0, 1.0) * 255).toInt()
        return (baseColor and 0x00FFFFFF) or (alpha shl 24)
    }

    private fun typefaceForWatermark(fontName: String): Typeface {
        ImportedFontStore.typeface(context, fontName)?.let { return it }
        val assetPath = when (fontName) {
            "pretendard_bold" -> "fonts/pretendard_bold.ttf"
            "kakao_big_sans" -> "fonts/kakao_big_sans_regular.ttf"
            "gowun_batang" -> "fonts/gowun_batang_regular.ttf"
            "gowun_dodum" -> "fonts/gowun_dodum_regular.ttf"
            "nanum_gothic" -> "fonts/nanum_gothic_regular.ttf"
            "cafe24_ssurround" -> "fonts/cafe24_ssurround.ttf"
            "puradak_gentle_gothic" -> "fonts/puradak_gentle_gothic.ttf"
            "tenada" -> "fonts/tenada.ttf"
            "do_hyeon" -> "fonts/do_hyeon_regular.ttf"
            "black_han_sans" -> "fonts/black_han_sans_regular.ttf"
            "maruburi" -> "fonts/maru_buri_regular.ttf"
            "ddulgi_mayo" -> "fonts/ddulgi_mayo.otf"
            "pretendard" -> "fonts/pretendard_regular.otf"
            else -> "fonts/pretendard_regular.otf"
        }
        return runCatching { Typeface.createFromAsset(context.assets, assetPath) }
            .getOrElse { Typeface.create(Typeface.SANS_SERIF, Typeface.NORMAL) }
    }

    private class FixedLineHeightSpan(private val lineHeightPx: Int) : LineHeightSpan {
        override fun chooseHeight(
            text: CharSequence?,
            start: Int,
            end: Int,
            spanstartv: Int,
            v: Int,
            fm: Paint.FontMetricsInt
        ) {
            val currentHeight = fm.descent - fm.ascent
            if (currentHeight <= 0) return
            val targetHeight = lineHeightPx.coerceAtLeast(currentHeight)
            val difference = targetHeight - currentHeight
            fm.descent += difference / 2
            fm.ascent -= difference - difference / 2
        }
    }

    private fun trimSingleVideoClip(
        clip: ClipItem,
        outputFile: File,
        onProgress: (Double) -> Unit
    ): Uri {
        val extractor = MediaExtractor()
        val muxer = MediaMuxer(outputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        try {
            extractor.setDataSource(context, clip.sourceUri, null)

            val trackMappings = mutableMapOf<Int, Int>()
            var maxInputSize = 256 * 1024
            for (trackIndex in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(trackIndex)
                val mime = format.getString(MediaFormat.KEY_MIME).orEmpty()
                if (mime.startsWith("video/") || mime.startsWith("audio/")) {
                    if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                        maxInputSize = maxOf(maxInputSize, format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE))
                    }
                    trackMappings[trackIndex] = muxer.addTrack(format)
                }
            }

            require(trackMappings.isNotEmpty()) { "영상 트랙을 찾지 못했습니다." }
            readOrientationDegrees(clip.sourceUri)?.let(muxer::setOrientationHint)

            trackMappings.keys.forEach(extractor::selectTrack)
            val startUs = (clip.trimStartSeconds * 1_000_000).toLong().coerceAtLeast(0)
            val endUs = ((clip.trimStartSeconds + clip.durationSeconds) * 1_000_000).toLong()
                .coerceAtLeast(startUs + 100_000)
            extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)

            val buffer = ByteBuffer.allocate(maxInputSize)
            val info = MediaCodec.BufferInfo()
            var firstSampleTimeUs = -1L
            var wroteSample = false
            muxer.start()
            onProgress(0.1)

            while (true) {
                val sampleTrackIndex = extractor.sampleTrackIndex
                if (sampleTrackIndex < 0) break
                val muxerTrackIndex = trackMappings[sampleTrackIndex]
                if (muxerTrackIndex == null) {
                    extractor.advance()
                    continue
                }

                val sampleTimeUs = extractor.sampleTime
                if (sampleTimeUs > endUs) break
                val sampleSize = extractor.readSampleData(buffer, 0)
                if (sampleSize < 0) break
                if (firstSampleTimeUs < 0) firstSampleTimeUs = sampleTimeUs

                info.set(
                    0,
                    sampleSize,
                    sampleTimeUs - firstSampleTimeUs,
                    mediaCodecFlagsForSample(extractor.sampleFlags)
                )
                muxer.writeSampleData(muxerTrackIndex, buffer, info)
                wroteSample = true
                val elapsed = (sampleTimeUs - startUs).coerceAtLeast(0)
                val total = (endUs - startUs).coerceAtLeast(1)
                onProgress((elapsed.toDouble() / total.toDouble()).coerceIn(0.1, 0.95))
                extractor.advance()
            }
            require(wroteSample && outputFile.length() > 0L) {
                "선택한 구간에서 내보낼 영상 데이터를 찾지 못했습니다."
            }
            onProgress(1.0)
            return Uri.fromFile(outputFile)
        } finally {
            runCatching { muxer.stop() }
            muxer.release()
            extractor.release()
            if (outputFile.length() <= 0L) {
                runCatching { outputFile.delete() }
            }
        }
    }

    private fun mediaCodecFlagsForSample(sampleFlags: Int): Int {
        var flags = 0
        if (sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) {
            flags = flags or MediaCodec.BUFFER_FLAG_KEY_FRAME
        }
        if (sampleFlags and MediaExtractor.SAMPLE_FLAG_PARTIAL_FRAME != 0) {
            flags = flags or MediaCodec.BUFFER_FLAG_PARTIAL_FRAME
        }
        return flags
    }

    private fun readOrientationDegrees(uri: Uri): Int? {
        return runCatching {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(context, uri)
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                    ?.toIntOrNull()
                    ?.takeIf { it != 0 }
            } finally {
                retriever.release()
            }
        }.getOrNull()
    }
}

private class ShadowLayerSpan(
    private val radius: Float,
    private val dx: Float,
    private val dy: Float,
    private val color: Int
) : CharacterStyle() {
    override fun updateDrawState(textPaint: TextPaint) {
        textPaint.setShadowLayer(radius, dx, dy, color)
    }
}

private class HanClipTypefaceSpan(
    private val typeface: Typeface
) : MetricAffectingSpan() {
    override fun updateMeasureState(textPaint: TextPaint) {
        textPaint.typeface = typeface
    }

    override fun updateDrawState(textPaint: TextPaint) {
        textPaint.typeface = typeface
    }
}
