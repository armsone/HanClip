package com.hanclip.android.core.media

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.ImageDecoder
import android.location.Geocoder
import android.media.ExifInterface
import android.media.FaceDetector
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import com.hanclip.android.core.model.ClipItem
import com.hanclip.android.core.model.ClipMediaKind
import com.hanclip.android.core.model.LivePhotoMode
import com.hanclip.android.core.model.VideoSegmentMode
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileInputStream
import java.io.RandomAccessFile
import java.nio.charset.StandardCharsets
import java.util.UUID
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

object MediaImportReader {
    private const val MaxWorkingMediaFiles = 80

    fun isMotionPhoto(context: Context, uri: Uri): Boolean {
        return runCatching {
            context.contentResolver.openAssetFileDescriptor(uri, "r")?.use { descriptor ->
                FileInputStream(descriptor.fileDescriptor).use { input ->
                    val probe = ByteArray(512 * 1024)
                    val read = input.read(probe)
                    if (read <= 0) {
                        false
                    } else {
                        val header = String(probe, 0, read, StandardCharsets.ISO_8859_1)
                        header.contains("MotionPhoto", ignoreCase = true) ||
                            header.contains("MicroVideo", ignoreCase = true)
                    }
                }
            } ?: false
        }.getOrDefault(false)
    }

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
        val sourceLocation = metadata?.location ?: readImageLocation(context, uri)
        val sourceLocationName = sourceLocation?.let { resolvePlaceName(context, it) }
        val localSourceUri = persistWorkingMedia(context, uri, mimeType)
        val motionPhoto = if (isImage) {
            extractMotionPhoto(localSourceUri)
        } else {
            null
        }
        val photoFingerprint = if (isImage) {
            makePhotoSimilarityFingerprint(context, localSourceUri)
        } else {
            emptyList()
        }
        val selectedDuration = min(defaultDurationSeconds, sourceDuration ?: defaultDurationSeconds)
        val peak = analysis?.peakTimeSeconds ?: ((sourceDuration ?: selectedDuration) / 2.0)

        ClipItem(
            id = UUID.randomUUID().toString(),
            sourceUri = motionPhoto?.videoUri ?: localSourceUri,
            thumbnailUri = localSourceUri,
            durationSeconds = max(0.1, selectedDuration),
            photoDurationSeconds = defaultDurationSeconds,
            livePhotoDurationSeconds = motionPhoto?.durationSeconds,
            livePhotoStillUri = localSourceUri.takeIf { motionPhoto != null },
            isLivePhoto = motionPhoto != null,
            livePhotoMode = LivePhotoMode.Still,
            mediaKind = when {
                isVideo -> ClipMediaKind.Video
                motionPhoto != null -> ClipMediaKind.LivePhoto
                else -> ClipMediaKind.Photo
            },
            sourceDurationSeconds = motionPhoto?.durationSeconds ?: sourceDuration,
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
            originalSourceUriString = uri.toString(),
            sourceLatitude = sourceLocation?.latitude,
            sourceLongitude = sourceLocation?.longitude,
            sourceLocationName = sourceLocationName,
            sourceWidth = metadata?.width ?: imageSize?.first ?: 1,
            sourceHeight = metadata?.height ?: imageSize?.second ?: 1
        )
    }

    private fun extractMotionPhoto(imageUri: Uri): MotionPhotoInfo? {
        val imageFile = imageUri.takeIf { it.scheme == "file" }?.path?.let(::File) ?: return null
        if (!imageFile.isFile || imageFile.length() < 16L) return null
        val mp4Start = findMotionVideoOffset(imageFile) ?: return null
        val videoFile = File(imageFile.parentFile, "motion-${imageFile.nameWithoutExtension}.mp4")
        runCatching {
            val input = FileInputStream(imageFile)
            videoFile.outputStream().use { output ->
                input.use { source ->
                    source.channel.position(mp4Start)
                    source.copyTo(output)
                }
            }
        }.getOrElse { return null }
        val durationSeconds = runCatching {
            MediaMetadataRetriever().let { retriever ->
                try {
                    retriever.setDataSource(videoFile.absolutePath)
                    retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                        ?.toLongOrNull()
                        ?.div(1_000.0)
                } finally {
                    retriever.release()
                }
            }
        }.getOrNull()?.takeIf { it >= 0.1 } ?: run {
            videoFile.delete()
            return null
        }
        return MotionPhotoInfo(Uri.fromFile(videoFile), durationSeconds)
    }

    private fun findMotionVideoOffset(imageFile: File): Long? {
        val length = imageFile.length()
        val scanStart = 0L
        val buffer = ByteArray(1024 * 1024)
        return runCatching {
            RandomAccessFile(imageFile, "r").use { input ->
                var position = scanStart
                while (position < length - 8L) {
                    input.seek(position)
                    val count = input.read(buffer)
                    if (count < 8) break
                    for (index in 4 until count - 3) {
                        if (buffer[index] == 'f'.code.toByte() &&
                            buffer[index + 1] == 't'.code.toByte() &&
                            buffer[index + 2] == 'y'.code.toByte() &&
                            buffer[index + 3] == 'p'.code.toByte()
                        ) {
                            val boxSize = ((buffer[index - 4].toInt() and 0xFF) shl 24) or
                                ((buffer[index - 3].toInt() and 0xFF) shl 16) or
                                ((buffer[index - 2].toInt() and 0xFF) shl 8) or
                                (buffer[index - 1].toInt() and 0xFF)
                            val candidate = position + index - 4L
                            if (boxSize in 8..1_048_576 && candidate > 2L) {
                                return@use candidate
                            }
                        }
                    }
                    position += (count - 8).coerceAtLeast(1)
                }
                null
            }
        }.getOrNull()
    }

    private data class MotionPhotoInfo(
        val videoUri: Uri,
        val durationSeconds: Double
    )

    private fun makePhotoSimilarityFingerprint(context: Context, uri: Uri): List<Int> {
        val bitmap = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val source = ImageDecoder.createSource(context.contentResolver, uri)
                ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                    val sourceWidth = info.size.width.coerceAtLeast(1)
                    val sourceHeight = info.size.height.coerceAtLeast(1)
                    val scale = min(1.0, 512.0 / max(sourceWidth, sourceHeight).toDouble())
                    decoder.setTargetSize(
                        (sourceWidth * scale).toInt().coerceAtLeast(2),
                        (sourceHeight * scale).toInt().coerceAtLeast(2)
                    )
                }
            } else {
                context.contentResolver.openInputStream(uri)?.use(BitmapFactory::decodeStream)
            }
        }.getOrNull() ?: return emptyList()

        val faceCount = detectFaceCount(bitmap)
        val scaled = Bitmap.createScaledBitmap(bitmap, 16, 16, true)
        val fingerprint = buildList(16 * 16 + 1) {
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
            add(faceCount.coerceIn(0, 255))
        }
        scaled.recycle()
        bitmap.recycle()
        return fingerprint
    }

    private fun detectFaceCount(source: Bitmap): Int {
        val scale = min(1.0, 512.0 / max(source.width, source.height).coerceAtLeast(1).toDouble())
        fun even(value: Int): Int {
            val safe = value.coerceAtLeast(2)
            return if (safe % 2 == 0) safe else safe - 1
        }
        val width = even((source.width * scale).toInt())
        val height = even((source.height * scale).toInt())
        val sized = if (source.width == width && source.height == height) {
            source
        } else {
            Bitmap.createScaledBitmap(source, width, height, true)
        }
        val rgb565 = sized.copy(Bitmap.Config.RGB_565, false) ?: run {
            if (sized !== source) sized.recycle()
            return 0
        }
        val faces = arrayOfNulls<FaceDetector.Face>(20)
        val count = runCatching {
            FaceDetector(rgb565.width, rgb565.height, faces.size).findFaces(rgb565, faces)
        }.getOrDefault(0)
        rgb565.recycle()
        if (sized !== source) sized.recycle()
        return count
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
                val location = retriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_LOCATION
                )?.let(::parseLocation)
                VideoMetadata(
                    durationSeconds = max(0.1, durationMs / 1000.0),
                    width = width,
                    height = height,
                    location = location
                )
            } finally {
                retriever.release()
            }
        }.getOrNull()
    }

    @Suppress("DEPRECATION")
    private fun readImageLocation(context: Context, uri: Uri): GeoPoint? = runCatching {
        context.contentResolver.openInputStream(uri)?.use { input ->
            val coordinates = FloatArray(2)
            if (ExifInterface(input).getLatLong(coordinates)) {
                GeoPoint(coordinates[0].toDouble(), coordinates[1].toDouble()).takeIf { it.isValid }
            } else {
                null
            }
        }
    }.getOrNull()

    private fun parseLocation(value: String): GeoPoint? {
        val normalized = value.trim().removeSuffix("/")
        val splitIndex = normalized.drop(1).indexOfAny(charArrayOf('+', '-'))
            .takeIf { it >= 0 }?.plus(1) ?: return null
        val latitude = normalized.substring(0, splitIndex).toDoubleOrNull() ?: return null
        val longitude = normalized.substring(splitIndex).toDoubleOrNull() ?: return null
        return GeoPoint(latitude, longitude).takeIf { it.isValid }
    }

    @Suppress("DEPRECATION")
    private fun resolvePlaceName(context: Context, point: GeoPoint): String = runCatching {
        val address = Geocoder(context, Locale.KOREAN)
            .getFromLocation(point.latitude, point.longitude, 1)
            ?.firstOrNull()
        val city = address?.locality ?: address?.subAdminArea ?: address?.adminArea
        if (address?.countryCode.equals("KR", ignoreCase = true)) {
            city
        } else {
            listOfNotNull(address?.countryName, city).distinct().joinToString(" ")
        }.orEmpty().ifBlank { point.readableText }
    }.getOrElse { point.readableText }

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
    val height: Int,
    val location: GeoPoint?
)

private data class GeoPoint(val latitude: Double, val longitude: Double) {
    val isValid: Boolean
        get() = latitude.isFinite() && longitude.isFinite() &&
            latitude in -90.0..90.0 && longitude in -180.0..180.0 &&
            !(kotlin.math.abs(latitude) < 0.000001 && kotlin.math.abs(longitude) < 0.000001)

    val readableText: String
        get() = String.format(Locale.KOREAN, "%.4f, %.4f", latitude, longitude)
}
