package com.hanclip.android.core.project

import android.content.Context
import android.graphics.Bitmap
import android.location.Geocoder
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.annotation.OptIn
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.ByteArrayOutputStream
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.time.Instant
import java.util.Date
import java.util.Locale
import java.util.UUID
import java.util.Collections
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.max
import kotlin.math.min
import kotlin.math.abs
import kotlin.math.sqrt

data class CollectedMovie(
    val id: String,
    val title: String,
    val videoFilename: String,
    val posterFilename: String,
    val createdAtMillis: Long,
    val durationSeconds: Double,
    val madeAtMillis: Long?,
    val shootingStartAtMillis: Long?,
    val shootingEndAtMillis: Long?,
    val locationName: String?,
    val contentSha256: String? = null,
    val isPinned: Boolean = false,
    val pinnedAtMillis: Long? = null,
    val posterSelectionVersion: Int? = null
)

data class CollectionMigrationResult(
    val importedCount: Int,
    val failedCount: Int
)

data class CollectionImportOutcome(
    val movie: CollectedMovie,
    val wasDuplicate: Boolean
)

enum class CollectionPosterEngine {
    DeviceAI,
    HanClipAI
}

data class CollectionPosterCandidate(
    val id: String,
    val imageData: ByteArray,
    val engine: CollectionPosterEngine,
    val timeSeconds: Double
)

enum class CollectionVideoSizeOption(
    val title: String,
    val detail: String,
    val shortSidePixels: Int,
    val targetBitsPerSecond: Int
) {
    High1080("1080p 고화질", "화질을 우선하면서 용량을 줄입니다.", 1080, 8_500_000),
    Saver720("720p 절약", "화질과 저장 공간의 균형을 맞춥니다.", 720, 5_000_000),
    Minimum540("540p 최소", "저장 공간을 가장 많이 절약합니다.", 540, 2_500_000);

    val resolutionLabel: String
        get() = when (this) {
            High1080 -> "1920×1080"
            Saver720 -> "1280×720"
            Minimum540 -> "960×540"
        }
}

data class CollectionVideoCompressionInfo(
    val width: Int,
    val height: Int,
    val durationSeconds: Double,
    val fileSizeBytes: Long
) {
    fun estimatedBytes(option: CollectionVideoSizeOption): Long {
        if (durationSeconds <= 0 || fileSizeBytes <= 0) return 0
        val sourceBitsPerSecond = fileSizeBytes * 8.0 / durationSeconds
        val sourcePixels = max(width.toDouble() * height.toDouble(), 1.0)
        val targetPixels = when (option) {
            CollectionVideoSizeOption.High1080 -> 1_920.0 * 1_080.0
            CollectionVideoSizeOption.Saver720 -> 1_280.0 * 720.0
            CollectionVideoSizeOption.Minimum540 -> 960.0 * 540.0
        }
        val pixelRatio = min(targetPixels / sourcePixels, 1.0)
        val adjustedRate = sourceBitsPerSecond * Math.pow(max(pixelRatio, 0.08), 0.72)
        val estimatedRate = min(
            sourceBitsPerSecond * 0.94,
            min(adjustedRate, option.targetBitsPerSecond.toDouble())
        )
        val estimated = (max(estimatedRate, 320_000.0) * durationSeconds / 8.0).toLong()
        return min(estimated, (fileSizeBytes * 0.98).toLong())
    }
}

data class CollectionVideoCompressionResult(
    val originalBytes: Long,
    val compressedBytes: Long
)

object MovieCollectionStore {
    const val MaximumMovieCount = 30
    private const val DirectoryName = "movie-collection"
    private const val IndexFilename = "collection.json"
    private const val MigrationPreferences = "hanclip_movie_collection_migration"
    private const val LegacyMigrationCompletedKey = "export_history_v1_completed"
    private const val MigratedLegacyUrisKey = "export_history_v1_imported_uris"
    private const val SchemaVersion = 4
    const val CurrentPosterSelectionVersion = 2
    private val collectionWriteLock = Any()

    fun list(context: Context): List<CollectedMovie> {
        val index = indexFile(context)
        val backup = File(collectionDirectory(context), "$IndexFilename.bak")
        return sequenceOf(index, backup)
            .filter(File::isFile)
            .mapNotNull { source -> parseIndex(context, source) }
            .firstOrNull()
            .orEmpty()
    }

    fun videoUri(context: Context, movie: CollectedMovie): Uri =
        Uri.fromFile(videoFile(context, movie))

    fun posterFile(context: Context, movie: CollectedMovie): File =
        File(collectionDirectory(context), movie.posterFilename)

    fun fileSizeInBytes(context: Context, movie: CollectedMovie): Long? =
        videoFile(context, movie).takeIf(File::isFile)?.length()?.takeIf { it > 0L }

    suspend fun compressionInfo(
        context: Context,
        movie: CollectedMovie
    ): CollectionVideoCompressionInfo? = withContext(Dispatchers.IO) {
        val file = videoFile(context.applicationContext, movie)
        if (!file.isFile || file.length() <= 0L) return@withContext null
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.absolutePath)
            val rawWidth = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull()?.coerceAtLeast(1) ?: 1
            val rawHeight = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull()?.coerceAtLeast(1) ?: 1
            val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull()?.mod(360) ?: 0
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull()?.div(1000.0) ?: movie.durationSeconds
            CollectionVideoCompressionInfo(
                width = if (rotation == 90 || rotation == 270) rawHeight else rawWidth,
                height = if (rotation == 90 || rotation == 270) rawWidth else rawHeight,
                durationSeconds = max(duration, 0.0),
                fileSizeBytes = file.length()
            )
        } finally {
            retriever.release()
        }
    }

    @OptIn(UnstableApi::class)
    suspend fun reduceFileSize(
        context: Context,
        movie: CollectedMovie,
        option: CollectionVideoSizeOption,
        onProgress: (Double) -> Unit
    ): CollectionVideoCompressionResult = withContext(Dispatchers.Main.immediate) {
        val appContext = context.applicationContext
        val currentMovie = withContext(Dispatchers.IO) {
            list(appContext).firstOrNull { it.id == movie.id }
        } ?: error("컬렉션에서 영상을 찾을 수 없습니다.")
        val sourceFile = videoFile(appContext, currentMovie)
        val originalBytes = sourceFile.length()
        require(originalBytes > 0L) { "컬렉션 영상을 읽을 수 없습니다." }
        val sourceInfo = compressionInfo(appContext, currentMovie)
            ?: error("컬렉션 영상 정보를 읽을 수 없습니다.")
        // Presentation can upscale a smaller source. iOS export presets keep smaller
        // originals at their native size, so cap the requested short side as well.
        val targetShortSide = min(
            min(sourceInfo.width, sourceInfo.height),
            option.shortSidePixels
        ).coerceAtLeast(1)
        val compressedFilename = "${movie.id}-compressed-${UUID.randomUUID()}.mp4"
        val outputFile = File(collectionDirectory(appContext), compressedFilename)
        outputFile.delete()

        val editedItem = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(sourceFile)))
            .setEffects(
                Effects(
                    Collections.emptyList(),
                    listOf<Effect>(Presentation.createForShortSide(targetShortSide))
                )
            )
            .build()
        val encoderFactory = DefaultEncoderFactory.Builder(appContext)
            .setEnableFallback(true)
            .setRequestedVideoEncoderSettings(
                VideoEncoderSettings.Builder()
                    .setBitrate(option.targetBitsPerSecond)
                    .build()
            )
            .build()

        suspendCancellableCoroutine { continuation ->
            var progressJob: Job? = null
            val transformer = Transformer.Builder(appContext)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .setEncoderFactory(encoderFactory)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        progressJob?.cancel()
                        if (continuation.isActive) continuation.resume(Unit)
                    }

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exportException: ExportException
                    ) {
                        progressJob?.cancel()
                        outputFile.delete()
                        if (continuation.isActive) continuation.resumeWithException(exportException)
                    }
                })
                .build()
            continuation.invokeOnCancellation {
                progressJob?.cancel()
                transformer.cancel()
                outputFile.delete()
            }
            onProgress(0.01)
            transformer.start(editedItem, outputFile.absolutePath)
            progressJob = CoroutineScope(Dispatchers.Main.immediate).launch {
                val holder = ProgressHolder()
                while (true) {
                    if (transformer.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) {
                        onProgress(holder.progress.coerceIn(0, 99) / 100.0)
                    }
                    delay(250)
                }
            }
        }

        val compressedBytes = outputFile.length()
        if (compressedBytes <= 0L || compressedBytes >= originalBytes) {
            outputFile.delete()
            error("변환 결과가 원본보다 작지 않아 원본 파일을 유지했습니다.")
        }
        withContext(Dispatchers.IO) {
            synchronized(collectionWriteLock) {
                val movies = list(appContext)
                val index = movies.indexOfFirst { it.id == movie.id }
                if (index < 0 || movies[index].videoFilename != currentMovie.videoFilename) {
                    outputFile.delete()
                    error("컬렉션 영상이 변경되어 원본을 유지했습니다.")
                }
                val updated = movies.toMutableList().apply {
                    this[index] = this[index].copy(
                        videoFilename = compressedFilename,
                        contentSha256 = sha256(outputFile)
                    )
                }
                try {
                    save(appContext, updated)
                    sourceFile.delete()
                } catch (error: Throwable) {
                    outputFile.delete()
                    throw error
                }
            }
        }
        onProgress(1.0)
        CollectionVideoCompressionResult(originalBytes, compressedBytes)
    }

    suspend fun posterCandidatesWithAI(
        context: Context,
        movie: CollectedMovie,
        generation: Int = 0
    ): List<CollectionPosterCandidate> = withContext(Dispatchers.IO) {
        val file = videoFile(context.applicationContext, movie)
        if (!file.isFile) return@withContext emptyList()
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.absolutePath)
            val safeDuration = movie.durationSeconds.coerceAtLeast(0.0)
            val phase = (generation.coerceAtLeast(0) % 17) * 0.011
            val analyzed = (0 until 36).mapNotNull { index ->
                currentCoroutineContext().ensureActive()
                val base = (index + 0.5) / 36.0
                val position = 0.02 + ((base + phase) % 1.0) * 0.96
                val seconds = safeDuration * position
                val frame = runCatching {
                    retriever.getFrameAtTime(
                        (seconds * 1_000_000L).toLong(),
                        MediaMetadataRetriever.OPTION_CLOSEST
                    )
                }.getOrNull() ?: return@mapNotNull null
                val scaled = frame.scaledToLongEdge(720)
                val scores = posterAIScores(scaled)
                val output = ByteArrayOutputStream()
                scaled.compress(Bitmap.CompressFormat.JPEG, 84, output)
                if (scaled !== frame) scaled.recycle()
                frame.recycle()
                AnalyzedPosterCandidate(
                    imageData = output.toByteArray(),
                    timeSeconds = seconds,
                    deviceScore = scores.first,
                    hanClipScore = scores.second
                )
            }
            val device = analyzed.sortedByDescending(AnalyzedPosterCandidate::deviceScore).take(8)
            val deviceTimes = device.map(AnalyzedPosterCandidate::timeSeconds)
            val hanClip = analyzed
                .filter { candidate -> deviceTimes.none { abs(it - candidate.timeSeconds) < 0.001 } }
                .sortedByDescending(AnalyzedPosterCandidate::hanClipScore)
                .take(8)
            device.map { it.toPublicCandidate(CollectionPosterEngine.DeviceAI) } +
                hanClip.map { it.toPublicCandidate(CollectionPosterEngine.HanClipAI) }
        } finally {
            retriever.release()
        }
    }

    fun applyPosterCandidate(
        context: Context,
        movie: CollectedMovie,
        imageData: ByteArray
    ) {
        synchronized(collectionWriteLock) {
            val target = posterFile(context, movie)
            val temporary = File(target.parentFile, "${target.name}.tmp")
            FileOutputStream(temporary).use { output ->
                output.write(imageData)
                output.fd.sync()
            }
            val backup = File(target.parentFile, "${target.name}.bak")
            backup.delete()
            if (target.exists() && !target.renameTo(backup)) {
                temporary.delete()
                error("기존 썸네일을 안전하게 보관하지 못했습니다.")
            }
            if (!temporary.renameTo(target)) {
                backup.renameTo(target)
                temporary.delete()
                error("선택한 썸네일을 저장하지 못했습니다.")
            }
            backup.delete()
            val updated = list(context).map { stored ->
                if (stored.id == movie.id) {
                    stored.copy(posterSelectionVersion = CurrentPosterSelectionVersion)
                } else {
                    stored
                }
            }
            save(context, updated)
        }
    }

    suspend fun regenerateOutdatedPosters(
        context: Context,
        onProgress: suspend (completed: Int, total: Int) -> Unit
    ): Int = withContext(Dispatchers.IO) {
        val appContext = context.applicationContext
        val outdated = list(appContext).filter {
            (it.posterSelectionVersion ?: 0) < CurrentPosterSelectionVersion
        }
        if (outdated.isEmpty()) return@withContext 0
        onProgress(0, outdated.size)
        var completed = 0
        outdated.forEach { movie ->
            currentCoroutineContext().ensureActive()
            val video = videoFile(appContext, movie)
            val target = posterFile(appContext, movie)
            val temporary = File(target.parentFile, "${target.name}.ai.tmp")
            temporary.delete()
            runCatching {
                writePoster(video, temporary, movie.durationSeconds)
                check(temporary.isFile && temporary.length() > 0L)
                synchronized(collectionWriteLock) {
                    val current = list(appContext)
                    val stored = current.firstOrNull { it.id == movie.id }
                        ?: return@synchronized
                    val backup = File(target.parentFile, "${target.name}.ai.bak")
                    backup.delete()
                    if (target.exists() && !target.renameTo(backup)) {
                        error("기존 썸네일을 안전하게 보관하지 못했습니다.")
                    }
                    if (!temporary.renameTo(target)) {
                        backup.renameTo(target)
                        error("AI 썸네일을 저장하지 못했습니다.")
                    }
                    backup.delete()
                    save(
                        appContext,
                        current.map {
                            if (it.id == stored.id) {
                                it.copy(posterSelectionVersion = CurrentPosterSelectionVersion)
                            } else {
                                it
                            }
                        }
                    )
                }
            }
            temporary.delete()
            completed += 1
            onProgress(completed, outdated.size)
        }
        completed
    }

    suspend fun importMovie(
        context: Context,
        sourceUri: Uri,
        title: String? = null,
        madeAtMillis: Long? = null,
        shootingStartAtMillis: Long? = null,
        shootingEndAtMillis: Long? = null,
        locationName: String? = null
    ): CollectedMovie = importMovieWithOutcome(
        context = context,
        sourceUri = sourceUri,
        title = title,
        madeAtMillis = madeAtMillis,
        shootingStartAtMillis = shootingStartAtMillis,
        shootingEndAtMillis = shootingEndAtMillis,
        locationName = locationName
    ).movie

    suspend fun importMovieWithOutcome(
        context: Context,
        sourceUri: Uri,
        title: String? = null,
        madeAtMillis: Long? = null,
        shootingStartAtMillis: Long? = null,
        shootingEndAtMillis: Long? = null,
        locationName: String? = null
    ): CollectionImportOutcome = withContext(Dispatchers.IO) {
        val cancellationContext = currentCoroutineContext()
        synchronized(collectionWriteLock) {
            val appContext = context.applicationContext
            require(isVideo(appContext, sourceUri)) { "동영상 파일만 컬렉션에 추가할 수 있습니다." }

            val id = UUID.randomUUID().toString()
            val extension = sourceExtension(appContext, sourceUri)
            val videoFilename = "$id.$extension"
            val posterFilename = "$id.jpg"
            val destination = File(collectionDirectory(appContext), videoFilename)
            val poster = File(collectionDirectory(appContext), posterFilename)
            val existing = list(appContext)
            check(existing.size < MaximumMovieCount) {
                "컬렉션에는 영화를 최대 ${MaximumMovieCount}개까지 보관할 수 있습니다."
            }

            try {
                val sourceHash = copySource(appContext, sourceUri, destination, cancellationContext)
                val existingWithHashes = existing.map { movie ->
                    movie.takeIf { it.contentSha256 != null }
                        ?: movie.copy(contentSha256 = sha256(videoFile(appContext, movie)))
                }
                existingWithHashes.firstOrNull { it.contentSha256 == sourceHash }?.let { duplicate ->
                    destination.delete()
                    if (existingWithHashes != existing) save(appContext, existingWithHashes)
                    return@synchronized CollectionImportOutcome(duplicate, wasDuplicate = true)
                }

                val metadata = readMetadata(appContext, destination)
                writePoster(destination, poster, metadata.durationSeconds)
                val resolvedMadeAt = madeAtMillis ?: metadata.creationDateMillis
                    ?: sourceLastModified(appContext, sourceUri)
                val resolvedStartAt = shootingStartAtMillis
                    ?: metadata.shootingStartAtMillis
                    ?: resolvedMadeAt
                val resolvedEndAt = shootingEndAtMillis
                    ?: metadata.shootingEndAtMillis
                    ?: resolvedStartAt
                val movie = CollectedMovie(
                    id = id,
                    title = title?.trim()?.takeIf(String::isNotEmpty)
                        ?: resolvedMadeAt?.let(::dateTitle)
                        ?: displayName(appContext, sourceUri).substringBeforeLast('.')
                            .ifBlank { "새 영화" },
                    videoFilename = videoFilename,
                    posterFilename = posterFilename,
                    createdAtMillis = System.currentTimeMillis(),
                    durationSeconds = metadata.durationSeconds,
                    madeAtMillis = resolvedMadeAt,
                    shootingStartAtMillis = resolvedStartAt,
                    shootingEndAtMillis = resolvedEndAt,
                    locationName = locationName?.trim()?.takeIf(String::isNotEmpty)
                        ?: metadata.locationName,
                    contentSha256 = sourceHash,
                    isPinned = false,
                    posterSelectionVersion = CurrentPosterSelectionVersion
                )
                save(appContext, existingWithHashes + movie)
                CollectionImportOutcome(movie, wasDuplicate = false)
            } catch (error: Throwable) {
                destination.delete()
                poster.delete()
                throw error
            }
        }
    }

    suspend fun migrateLegacyHistory(context: Context): CollectionMigrationResult =
        withContext(Dispatchers.IO) {
            val appContext = context.applicationContext
            val preferences = appContext.getSharedPreferences(
                MigrationPreferences,
                Context.MODE_PRIVATE
            )
            if (preferences.getBoolean(LegacyMigrationCompletedKey, false)) {
                return@withContext CollectionMigrationResult(0, 0)
            }

            var importedCount = 0
            var failedCount = 0
            val migratedUris = preferences.getStringSet(MigratedLegacyUrisKey, emptySet())
                .orEmpty()
                .toMutableSet()
            val legacyItems = ExportHistoryStore.list(appContext)
            legacyItems.filterNot { it.uriString in migratedUris }.forEach { summary ->
                runCatching {
                    importMovie(
                        context = appContext,
                        sourceUri = Uri.parse(summary.uriString),
                        title = summary.memo.takeIf(String::isNotBlank) ?: summary.title,
                        madeAtMillis = summary.updatedAtMillis,
                        shootingStartAtMillis = summary.updatedAtMillis,
                        shootingEndAtMillis = summary.updatedAtMillis
                    )
                }.onSuccess {
                    importedCount += 1
                    migratedUris += summary.uriString
                }.onFailure {
                    failedCount += 1
                }
            }
            // 원본 ExportHistoryStore는 호환성과 데이터 복구를 위해 그대로 둔다.
            preferences.edit()
                .putStringSet(MigratedLegacyUrisKey, migratedUris)
                .putBoolean(
                    LegacyMigrationCompletedKey,
                    legacyItems.all { it.uriString in migratedUris }
                )
                .apply()
            CollectionMigrationResult(importedCount, failedCount)
        }

    fun updateTitle(context: Context, movieId: String, title: String) {
        val normalized = title.trim()
        if (normalized.isEmpty()) return
        synchronized(collectionWriteLock) {
            val updated = list(context).map { movie ->
                if (movie.id == movieId) movie.copy(title = normalized) else movie
            }
            save(context, updated)
        }
    }

    fun togglePin(context: Context, movieId: String) {
        synchronized(collectionWriteLock) {
            val updated = list(context).map { movie ->
                if (movie.id == movieId) {
                    val willPin = !movie.isPinned
                    movie.copy(
                        isPinned = willPin,
                        pinnedAtMillis = if (willPin) System.currentTimeMillis() else null
                    )
                } else movie
            }
            save(context, updated)
        }
    }

    fun movePinnedMovie(context: Context, sourceId: String, targetId: String) {
        if (sourceId == targetId) return
        synchronized(collectionWriteLock) {
            val movies = list(context)
            val pinned = movies.filter(CollectedMovie::isPinned).toMutableList()
            val sourceIndex = pinned.indexOfFirst { it.id == sourceId }
            val targetIndex = pinned.indexOfFirst { it.id == targetId }
            if (sourceIndex < 0 || targetIndex < 0) return
            val moved = pinned.removeAt(sourceIndex)
            val insertionIndex = if (sourceIndex < targetIndex) {
                targetIndex.coerceAtMost(pinned.size)
            } else {
                targetIndex
            }
            pinned.add(insertionIndex, moved)
            val reference = System.currentTimeMillis()
            val pinnedTimes = pinned.mapIndexed { index, movie ->
                movie.id to reference - index
            }.toMap()
            save(
                context,
                movies.map { movie ->
                    pinnedTimes[movie.id]?.let { movie.copy(pinnedAtMillis = it) } ?: movie
                }
            )
        }
    }

    fun remove(context: Context, movieId: String) {
        synchronized(collectionWriteLock) {
            val movies = list(context)
            val target = movies.firstOrNull { it.id == movieId } ?: return
            save(context, movies.filterNot { it.id == movieId })
            videoFile(context, target).delete()
            posterFile(context, target).delete()
        }
    }

    private fun save(context: Context, movies: List<CollectedMovie>) {
        val directory = collectionDirectory(context)
        val target = File(directory, IndexFilename)
        val temporary = File(directory, "$IndexFilename.tmp")
        val root = JSONObject()
            .put("schemaVersion", SchemaVersion)
            .put("movies", JSONArray().apply {
                movies.sortedForDisplay().forEach { movie ->
                    put(movie.toJson())
                }
            })
        FileOutputStream(temporary).use { output ->
            output.write(root.toString().toByteArray(Charsets.UTF_8))
            output.fd.sync()
        }
        val backup = File(directory, "$IndexFilename.bak")
        backup.delete()
        if (target.exists() && !target.renameTo(backup)) {
            temporary.delete()
            error("컬렉션 목록을 갱신하지 못했습니다.")
        }
        if (!temporary.renameTo(target)) {
            if (backup.exists()) backup.renameTo(target)
            temporary.delete()
            error("컬렉션 목록을 저장하지 못했습니다.")
        }
        backup.delete()
    }

    private fun collectionDirectory(context: Context): File =
        File(context.filesDir, DirectoryName).apply { mkdirs() }

    private fun indexFile(context: Context): File =
        File(collectionDirectory(context), IndexFilename)

    private fun videoFile(context: Context, movie: CollectedMovie): File =
        File(collectionDirectory(context), movie.videoFilename)

    private fun parseIndex(context: Context, source: File): List<CollectedMovie>? = runCatching {
        val root = JSONObject(source.readText())
        val items = root.optJSONArray("movies") ?: JSONArray()
        List(items.length()) { position -> items.getJSONObject(position).toCollectedMovie() }
            .filter { movie ->
                videoFile(context, movie).isFile && videoFile(context, movie).canRead()
            }
            .sortedForDisplay()
    }.getOrNull()

    private fun copySource(
        context: Context,
        sourceUri: Uri,
        destination: File,
        cancellationContext: CoroutineContext
    ): String {
        val input = when (sourceUri.scheme) {
            "file" -> sourceUri.path?.let(::File)?.inputStream()
            else -> context.contentResolver.openInputStream(sourceUri)
        } ?: error("선택한 동영상을 읽을 수 없습니다.")
        val digest = MessageDigest.getInstance("SHA-256")
        input.use { source ->
            java.security.DigestInputStream(source, digest).use { digestSource ->
                destination.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        cancellationContext.ensureActive()
                        val count = digestSource.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                    }
                }
            }
        }
        require(destination.length() > 0L) { "빈 동영상 파일은 추가할 수 없습니다." }
        return digest.digest().toHexString()
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { source ->
            java.security.DigestInputStream(source, digest).use { digestSource ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                while (digestSource.read(buffer) >= 0) Unit
            }
        }
        return digest.digest().toHexString()
    }

    private fun ByteArray.toHexString(): String = joinToString("") { byte -> "%02x".format(byte) }

    private data class SourceMetadata(
        val durationSeconds: Double,
        val creationDateMillis: Long?,
        val shootingStartAtMillis: Long?,
        val shootingEndAtMillis: Long?,
        val locationName: String?
    )

    private fun readMetadata(context: Context, file: File): SourceMetadata {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.absolutePath)
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toDoubleOrNull()?.div(1_000.0)?.coerceAtLeast(0.0) ?: 0.0
            val embedded = readHanClipMetadata(file)
            val date = embedded?.madeAtMillis ?: retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DATE)
                ?.let(::parseMetadataDate)
            val location = embedded?.locationName ?: retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_LOCATION)
                    ?.let(::parseLocation)
                    ?.let { point -> resolvePlaceName(context, point) ?: point.readableText }
            SourceMetadata(
                durationSeconds = duration,
                creationDateMillis = date,
                shootingStartAtMillis = embedded?.shootingStartAtMillis,
                shootingEndAtMillis = embedded?.shootingEndAtMillis,
                locationName = location
            )
        } finally {
            retriever.release()
        }
    }

    private data class EmbeddedHanClipMetadata(
        val madeAtMillis: Long?,
        val shootingStartAtMillis: Long?,
        val shootingEndAtMillis: Long?,
        val locationName: String?
    )

    private fun readHanClipMetadata(file: File): EmbeddedHanClipMetadata? = runCatching {
        val marker = "\"marker\":\"HANCLIP_METADATA\"".toByteArray(Charsets.UTF_8)
        val iosPrefix = "HANCLIP_METADATA:".toByteArray(Charsets.UTF_8)
        val readBuffer = ByteArray(64 * 1024)
        var carry = ByteArray(0)
        RandomAccessFile(file, "r").use { source ->
            while (true) {
                val count = source.read(readBuffer)
                if (count < 0) break
                val window = carry + readBuffer.copyOf(count)
                val markerIndex = window.indexOfSequence(marker)
                if (markerIndex >= 0) {
                    val jsonStart = window.lastIndexOfByte('{'.code.toByte(), markerIndex)
                    val jsonEnd = window.indexOfByte('}'.code.toByte(), markerIndex)
                    if (jsonStart >= 0 && jsonEnd > jsonStart) {
                        val json = JSONObject(
                            window.copyOfRange(jsonStart, jsonEnd + 1).toString(Charsets.UTF_8)
                        )
                        if (json.optString("marker") == "HANCLIP_METADATA") {
                            return@runCatching EmbeddedHanClipMetadata(
                                madeAtMillis = json.optionalLong("madeAtMillis"),
                                shootingStartAtMillis = json.optionalLong("shootingStartAtMillis"),
                                shootingEndAtMillis = json.optionalLong("shootingEndAtMillis"),
                                locationName = json.optionalString("locationName")
                            )
                        }
                    }
                }
                val iosPrefixIndex = window.indexOfSequence(iosPrefix)
                if (iosPrefixIndex >= 0) {
                    val jsonStart = iosPrefixIndex + iosPrefix.size
                    val jsonEnd = window.indexOfByte('}'.code.toByte(), jsonStart)
                    if (jsonEnd > jsonStart) {
                        val json = JSONObject(
                            window.copyOfRange(jsonStart, jsonEnd + 1).toString(Charsets.UTF_8)
                        )
                        val routeNames = json.optJSONArray("routeLocationNames")
                            ?.let { routes ->
                                buildList {
                                    repeat(routes.length()) { index ->
                                        routes.optString(index)
                                            .trim()
                                            .takeIf(String::isNotEmpty)
                                            ?.let(::add)
                                    }
                                }
                            }
                            .orEmpty()
                        return@runCatching EmbeddedHanClipMetadata(
                            madeAtMillis = null,
                            shootingStartAtMillis = json.optionalIsoInstantMillis("shootingStartAt"),
                            shootingEndAtMillis = json.optionalIsoInstantMillis("shootingEndAt"),
                            locationName = json.optionalString("locationName")
                                ?: routeNames.takeIf(List<String>::isNotEmpty)?.joinToString(" → ")
                        )
                    }
                }
                carry = window.copyOfRange(
                    max(0, window.size - 8 * 1024),
                    window.size
                )
            }
        }
        null
    }.getOrNull()

    private fun ByteArray.indexOfSequence(sequence: ByteArray): Int {
        if (sequence.isEmpty() || sequence.size > size) return -1
        for (start in 0..size - sequence.size) {
            var matches = true
            for (index in sequence.indices) {
                if (this[start + index] != sequence[index]) {
                    matches = false
                    break
                }
            }
            if (matches) return start
        }
        return -1
    }

    private fun ByteArray.lastIndexOfByte(value: Byte, before: Int): Int {
        for (index in min(before, lastIndex) downTo 0) {
            if (this[index] == value) return index
        }
        return -1
    }

    private fun ByteArray.indexOfByte(value: Byte, after: Int): Int {
        for (index in max(0, after)..lastIndex) {
            if (this[index] == value) return index
        }
        return -1
    }

    private fun writePoster(video: File, target: File, durationSeconds: Double) {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(video.absolutePath)
            val frames = (0 until 12).mapNotNull { index ->
                val seconds = durationSeconds.coerceAtLeast(0.0) * (index + 0.5) / 12.0
                val frame = runCatching {
                    retriever.getFrameAtTime(
                        (seconds * 1_000_000L).toLong(),
                        MediaMetadataRetriever.OPTION_CLOSEST
                    )
                }.getOrNull() ?: return@mapNotNull null
                val scaled = frame.scaledToLongEdge(1080)
                if (scaled !== frame) frame.recycle()
                scaled
            }
            val selected = frames.maxByOrNull { posterAIScores(it).second } ?: return
            target.outputStream().use { output ->
                selected.compress(Bitmap.CompressFormat.JPEG, 84, output)
            }
            frames.forEach(Bitmap::recycle)
        } finally {
            retriever.release()
        }
    }

    private data class AnalyzedPosterCandidate(
        val imageData: ByteArray,
        val timeSeconds: Double,
        val deviceScore: Double,
        val hanClipScore: Double
    ) {
        fun toPublicCandidate(engine: CollectionPosterEngine) = CollectionPosterCandidate(
            id = "$engine:$timeSeconds",
            imageData = imageData,
            engine = engine,
            timeSeconds = timeSeconds
        )
    }

    private fun posterAIScores(bitmap: Bitmap): Pair<Double, Double> {
        val stepX = max(1, bitmap.width / 72)
        val stepY = max(1, bitmap.height / 72)
        var count = 0
        var sum = 0.0
        var sumSquares = 0.0
        var edges = 0.0
        var previous = -1.0
        var y = 0
        while (y < bitmap.height) {
            var x = 0
            while (x < bitmap.width) {
                val color = bitmap.getPixel(x, y)
                val luminance = (
                    android.graphics.Color.red(color) * 0.2126 +
                        android.graphics.Color.green(color) * 0.7152 +
                        android.graphics.Color.blue(color) * 0.0722
                    )
                sum += luminance
                sumSquares += luminance * luminance
                if (previous >= 0) edges += abs(luminance - previous)
                previous = luminance
                count += 1
                x += stepX
            }
            y += stepY
        }
        if (count == 0) return 0.0 to 0.0
        val mean = sum / count
        val deviation = sqrt(max(0.0, sumSquares / count - mean * mean))
        val edgeStrength = edges / max(1, count - 1)
        val exposure = max(0.0, 1.0 - abs(mean - 128.0) / 128.0)
        val darkPenalty = if (mean < 16) 100.0 else 0.0
        val brightPenalty = if (mean > 244) 65.0 else 0.0
        val device = exposure * 28 + min(deviation / 58.0, 1.0) * 20 +
            min(edgeStrength / 42.0, 1.0) * 32 - darkPenalty - brightPenalty
        val hanClip = exposure * 20 + min(deviation / 58.0, 1.0) * 30 +
            min(edgeStrength / 42.0, 1.0) * 30 - darkPenalty - brightPenalty
        return device to hanClip
    }

    private fun Bitmap.scaledToLongEdge(maxLongEdge: Int): Bitmap {
        val longEdge = max(width, height)
        if (longEdge <= maxLongEdge) return this
        val scale = maxLongEdge.toDouble() / longEdge.toDouble()
        return Bitmap.createScaledBitmap(
            this,
            max(1, (width * scale).toInt()),
            max(1, (height * scale).toInt()),
            true
        )
    }

    private fun isVideo(context: Context, uri: Uri): Boolean {
        val mime = context.contentResolver.getType(uri).orEmpty()
        if (mime.startsWith("video/")) return true
        return uri.lastPathSegment.orEmpty().substringAfterLast('.', "").lowercase() in
            setOf("mp4", "mov", "m4v", "3gp", "webm", "mkv")
    }

    private fun sourceExtension(context: Context, uri: Uri): String {
        val mimeExtension = context.contentResolver.getType(uri)
            ?.let(MimeTypeMap.getSingleton()::getExtensionFromMimeType)
        val nameExtension = displayName(context, uri).substringAfterLast('.', "")
        return (mimeExtension ?: nameExtension)
            .lowercase()
            .takeIf { it.matches(Regex("[a-z0-9]{1,5}")) }
            ?: "mp4"
    }

    private fun displayName(context: Context, uri: Uri): String {
        if (uri.scheme == "file") return uri.lastPathSegment.orEmpty().ifBlank { "새 영화" }
        return runCatching {
            context.contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null
            )?.use { cursor ->
                if (!cursor.moveToFirst()) return@use null
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                index.takeIf { it >= 0 }?.let(cursor::getString)
            }
        }.getOrNull().orEmpty().ifBlank { uri.lastPathSegment ?: "새 영화" }
    }

    private fun sourceLastModified(context: Context, uri: Uri): Long? = runCatching {
        context.contentResolver.query(
            uri,
            arrayOf(DocumentsContract.Document.COLUMN_LAST_MODIFIED),
            null,
            null,
            null
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return@use null
            val index = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            index.takeIf { it >= 0 }?.let(cursor::getLong)?.takeIf { it > 0L }
        }
    }.getOrNull()

    private fun parseMetadataDate(value: String): Long? {
        val patterns = listOf(
            "yyyyMMdd'T'HHmmss.SSS'Z'",
            "yyyyMMdd'T'HHmmss'Z'",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXX"
        )
        return patterns.firstNotNullOfOrNull { pattern ->
            runCatching {
                SimpleDateFormat(pattern, Locale.US).apply { isLenient = false }
                    .parse(value)?.time
            }.getOrNull()
        }
    }

    private data class GeoPoint(val latitude: Double, val longitude: Double) {
        val readableText: String
            get() = String.format(Locale.KOREAN, "%.4f, %.4f", latitude, longitude)
    }

    private fun parseLocation(value: String): GeoPoint? {
        val normalized = value.trim().removeSuffix("/")
        if (normalized.isEmpty()) return null
        val splitIndex = normalized.drop(1).indexOfAny(charArrayOf('+', '-'))
            .takeIf { it >= 0 }?.plus(1) ?: return null
        val latitude = normalized.substring(0, splitIndex).toDoubleOrNull() ?: return null
        val longitude = normalized.substring(splitIndex).toDoubleOrNull() ?: return null
        return GeoPoint(latitude, longitude)
    }

    @Suppress("DEPRECATION")
    private fun resolvePlaceName(context: Context, point: GeoPoint): String? = runCatching {
        val englishAddress = Geocoder(context, Locale.ENGLISH)
            .getFromLocation(point.latitude, point.longitude, 1)
            ?.firstOrNull() ?: return@runCatching null
        val address = if (englishAddress.countryCode.equals("KR", ignoreCase = true)) {
            Geocoder(context, Locale.KOREAN)
                .getFromLocation(point.latitude, point.longitude, 1)
                ?.firstOrNull() ?: englishAddress
        } else {
            englishAddress
        }
        val city = address.locality
            ?: address.subAdminArea
            ?: address.adminArea
            ?: address.featureName
        if (address.countryCode.equals("KR", ignoreCase = true)) {
            city
        } else {
            listOfNotNull(address.countryName, city).distinct().joinToString(" ")
        }.takeIf(String::isNotBlank)
    }.getOrNull()

    private fun dateTitle(millis: Long): String =
        SimpleDateFormat("yyyy. M. d. (EEE)", Locale.KOREAN).format(Date(millis))

    private fun CollectedMovie.toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("title", title)
        .put("videoFilename", videoFilename)
        .put("posterFilename", posterFilename)
        .put("createdAtMillis", createdAtMillis)
        .put("durationSeconds", durationSeconds)
        .putNullable("madeAtMillis", madeAtMillis)
        .putNullable("shootingStartAtMillis", shootingStartAtMillis)
        .putNullable("shootingEndAtMillis", shootingEndAtMillis)
        .putNullable("locationName", locationName)
        .putNullable("contentSha256", contentSha256)
        .put("isPinned", isPinned)
        .putNullable("pinnedAtMillis", pinnedAtMillis)
        .putNullable("posterSelectionVersion", posterSelectionVersion)

    private fun JSONObject.toCollectedMovie(): CollectedMovie = CollectedMovie(
        id = getString("id"),
        title = optString("title", "새 영화"),
        videoFilename = getString("videoFilename"),
        posterFilename = optString("posterFilename", ""),
        createdAtMillis = optLong("createdAtMillis", 0L),
        durationSeconds = optDouble("durationSeconds", 0.0),
        madeAtMillis = optionalLong("madeAtMillis"),
        shootingStartAtMillis = optionalLong("shootingStartAtMillis"),
        shootingEndAtMillis = optionalLong("shootingEndAtMillis"),
        locationName = if (has("locationName") && !isNull("locationName")) {
            optString("locationName", "")
                .takeIf(String::isNotBlank)
                ?.takeUnless { it.equals("null", ignoreCase = true) }
        } else {
            null
        },
        contentSha256 = optionalString("contentSha256"),
        isPinned = optBoolean("isPinned", false),
        pinnedAtMillis = optionalLong("pinnedAtMillis"),
        posterSelectionVersion = optionalInt("posterSelectionVersion")
    )

    private fun JSONObject.optionalInt(key: String): Int? =
        if (has(key) && !isNull(key)) optInt(key).takeIf { it >= 0 } else null

    private fun List<CollectedMovie>.sortedForDisplay(): List<CollectedMovie> =
        sortedWith(
            compareByDescending<CollectedMovie> { it.isPinned }
                .thenByDescending { if (it.isPinned) it.pinnedAtMillis ?: it.createdAtMillis else Long.MIN_VALUE }
                .thenByDescending { it.createdAtMillis }
        )

    private fun JSONObject.optionalString(key: String): String? =
        if (!has(key) || isNull(key)) null else optString(key, "")
            .takeIf(String::isNotBlank)
            ?.takeUnless { it.equals("null", ignoreCase = true) }

    private fun JSONObject.optionalLong(key: String): Long? =
        if (!has(key) || isNull(key)) null else optLong(key).takeIf { it > 0L }

    private fun JSONObject.optionalIsoInstantMillis(key: String): Long? =
        optionalString(key)?.let { value ->
            runCatching { Instant.parse(value).toEpochMilli() }.getOrNull()
        }

    private fun JSONObject.putNullable(key: String, value: Any?): JSONObject =
        put(key, value ?: JSONObject.NULL)
}
