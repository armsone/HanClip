package com.hanclip.android.core.media

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.ImageDecoder
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import com.hanclip.android.core.model.ClipItem
import com.hanclip.android.core.model.ClipMediaKind
import com.hanclip.android.core.model.VideoSegmentMode
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID
import kotlin.math.max
import kotlin.math.min

object MediaImportReader {
    private const val MaxWorkingMediaFiles = 80

    suspend fun makeClip(
        context: Context,
        uri: Uri,
        defaultDurationSeconds: Double,
        defaultVideoSegmentMode: VideoSegmentMode
    ): ClipItem = withContext(Dispatchers.IO) {
        val mimeType = resolvedMimeType(context, uri)
        val isVideo = mimeType.startsWith("video/")
        val isImage = mimeType.startsWith("image/")
        require(isVideo || isImage) { "지원하지 않는 미디어 형식입니다." }
        val metadata = if (isVideo) readVideoMetadata(context, uri) else null
        val imageSize = if (!isVideo) readImageSize(context, uri) else null
        val sourceDuration = metadata?.durationSeconds
        val analysis = if (isVideo && sourceDuration != null) {
            AudioAnalysisService.analyze(context, uri, sourceDuration)
        } else {
            null
        }
        val sourceCreatedAtMillis = readSourceCreatedAtMillis(context, uri)
        val localSourceUri = persistWorkingMedia(context, uri, mimeType)
        val photoFingerprint = if (isImage) {
            makePhotoSimilarityFingerprint(context, localSourceUri)
        } else {
            emptyList()
        }
        val selectedDuration = min(defaultDurationSeconds, sourceDuration ?: defaultDurationSeconds)
        val peak = analysis?.peakTimeSeconds ?: ((sourceDuration ?: selectedDuration) / 2.0)

        ClipItem(
            id = UUID.randomUUID().toString(),
            sourceUri = localSourceUri,
            thumbnailUri = localSourceUri,
            durationSeconds = max(0.1, selectedDuration),
            photoDurationSeconds = defaultDurationSeconds,
            mediaKind = if (isVideo) ClipMediaKind.Video else ClipMediaKind.Photo,
            sourceDurationSeconds = sourceDuration,
            trimStartSeconds = if (isVideo && sourceDuration != null) {
                max(0.0, min(sourceDuration - selectedDuration, peak - selectedDuration / 2.0))
            } else {
                0.0
            },
            audioWaveform = analysis?.waveform ?: emptyList(),
            audioPeakTimeSeconds = analysis?.peakTimeSeconds,
            audioPeakTimesSeconds = analysis?.peakTimesSeconds ?: emptyList(),
            videoSegmentMode = if (isVideo) defaultVideoSegmentMode else VideoSegmentMode.Single,
            photoSimilarityFingerprint = photoFingerprint,
            sourceCreatedAtMillis = sourceCreatedAtMillis,
            sourceWidth = metadata?.width ?: imageSize?.first ?: 1,
            sourceHeight = metadata?.height ?: imageSize?.second ?: 1
        )
    }

    private fun makePhotoSimilarityFingerprint(context: Context, uri: Uri): List<Int> {
        val bitmap = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val source = ImageDecoder.createSource(context.contentResolver, uri)
                ImageDecoder.decodeBitmap(source) { decoder, _, _ ->
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                    decoder.setTargetSize(16, 16)
                }
            } else {
                context.contentResolver.openInputStream(uri)?.use(BitmapFactory::decodeStream)
            }
        }.getOrNull() ?: return emptyList()

        val scaled = if (bitmap.width == 16 && bitmap.height == 16) {
            bitmap
        } else {
            Bitmap.createScaledBitmap(bitmap, 16, 16, true)
        }
        val fingerprint = buildList(16 * 16) {
            for (y in 0 until 16) {
                for (x in 0 until 16) {
                    val pixel = scaled.getPixel(x, y)
                    val luminance = (
                        Color.red(pixel) * 0.299 +
                            Color.green(pixel) * 0.587 +
                            Color.blue(pixel) * 0.114
                        ).toInt().coerceIn(0, 255)
                    add(luminance)
                }
            }
        }
        if (scaled !== bitmap) scaled.recycle()
        bitmap.recycle()
        return fingerprint
    }

    private fun readSourceCreatedAtMillis(context: Context, uri: Uri): Long? {
        return runCatching {
            context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (!cursor.moveToFirst()) return@use null
                val takenAt = cursor.getColumnIndex(MediaStore.MediaColumns.DATE_TAKEN)
                    .takeIf { it >= 0 }
                    ?.let(cursor::getLong)
                    ?.takeIf { it > 0L }
                if (takenAt != null) return@use takenAt

                cursor.getColumnIndex(MediaStore.MediaColumns.DATE_ADDED)
                    .takeIf { it >= 0 }
                    ?.let(cursor::getLong)
                    ?.takeIf { it > 0L }
                    ?.times(1_000L)
            }
        }.getOrNull()
    }

    private fun persistWorkingMedia(context: Context, uri: Uri, mimeType: String): Uri {
        val extension = MimeTypeMap.getSingleton()
            .getExtensionFromMimeType(mimeType)
            ?.takeIf { it.isNotBlank() }
            ?: uri.lastPathSegment
                ?.substringAfterLast('.', missingDelimiterValue = "")
                ?.takeIf { it.isNotBlank() && it.length <= 5 }
            ?: if (mimeType.startsWith("video/")) "mp4" else "jpg"
        val directory = File(context.filesDir, "working-media").apply { mkdirs() }
        pruneDirectory(directory, MaxWorkingMediaFiles)
        val target = File(directory, "hanclip-${UUID.randomUUID()}.$extension")
        context.contentResolver.openInputStream(uri)?.use { input ->
            target.outputStream().use { output ->
                input.copyTo(output)
            }
        } ?: error("미디어 원본을 열 수 없습니다.")
        return Uri.fromFile(target)
    }

    private fun resolvedMimeType(context: Context, uri: Uri): String {
        val resolverType = context.contentResolver.getType(uri).orEmpty()
        if (resolverType.isNotBlank()) return resolverType

        val extension = uri.lastPathSegment
            ?.substringAfterLast('.', missingDelimiterValue = "")
            ?.lowercase()
            .orEmpty()
        val mappedType = MimeTypeMap.getSingleton()
            .getMimeTypeFromExtension(extension)
            .orEmpty()
        if (mappedType.isNotBlank()) return mappedType

        return when (extension) {
            "mp4", "m4v", "mov", "3gp", "webm", "mkv" -> "video/mp4"
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "heic", "heif" -> "image/heic"
            else -> ""
        }
    }

    private fun pruneDirectory(directory: File, maxFiles: Int) {
        val files = directory.listFiles()
            ?.filter { it.isFile }
            ?.sortedByDescending { it.lastModified() }
            .orEmpty()
        files.drop(maxFiles).forEach { file ->
            runCatching { file.delete() }
        }
    }

    suspend fun loadThumbnailBitmap(
        context: Context,
        uri: Uri,
        mediaKind: ClipMediaKind,
        targetSize: Int = 320
    ): Bitmap? = withContext(Dispatchers.IO) {
        runCatching {
            if (mediaKind == ClipMediaKind.Video) {
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(context, uri)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                        retriever.getScaledFrameAtTime(
                            0,
                            MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                            targetSize,
                            targetSize
                        ) ?: retriever.frameAtTime
                    } else {
                        retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                            ?: retriever.frameAtTime
                    }
                } finally {
                    retriever.release()
                }
            } else {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    val source = ImageDecoder.createSource(context.contentResolver, uri)
                    ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                        val scale = min(
                            targetSize.toDouble() / max(1, info.size.width).toDouble(),
                            targetSize.toDouble() / max(1, info.size.height).toDouble()
                        ).coerceAtMost(1.0)
                        decoder.setTargetSize(
                            max(1, (info.size.width * scale).toInt()),
                            max(1, (info.size.height * scale).toInt())
                        )
                    }
                } else {
                    context.contentResolver.openInputStream(uri)?.use { input ->
                        BitmapFactory.decodeStream(input)
                    }
                }
            }
        }.getOrNull()
    }

    private fun readVideoMetadata(context: Context, uri: Uri): VideoMetadata? {
        return runCatching {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(context, uri)
                val durationMs = retriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_DURATION
                )?.toLongOrNull() ?: 0L
                val width = retriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH
                )?.toIntOrNull() ?: 1
                val height = retriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT
                )?.toIntOrNull() ?: 1
                VideoMetadata(
                    durationSeconds = max(0.1, durationMs / 1000.0),
                    width = width,
                    height = height
                )
            } finally {
                retriever.release()
            }
        }.getOrNull()
    }

    private fun readImageSize(context: Context, uri: Uri): Pair<Int, Int>? {
        return runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                var decodedSize: Pair<Int, Int>? = null
                val source = ImageDecoder.createSource(context.contentResolver, uri)
                ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                    decodedSize = info.size.width to info.size.height
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                    decoder.setTargetSize(1, 1)
                }.recycle()
                return@runCatching decodedSize
            }
            val options = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            context.contentResolver.openInputStream(uri)?.use { input ->
                BitmapFactory.decodeStream(input, null, options)
            }
            val width = options.outWidth
            val height = options.outHeight
            if (width > 0 && height > 0) width to height else null
        }.getOrNull()
    }
}

private data class VideoMetadata(
    val durationSeconds: Double,
    val width: Int,
    val height: Int
)
