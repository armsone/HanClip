package com.hanclip.android.core.project

import android.content.Context
import android.graphics.Bitmap
import android.location.Geocoder
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import kotlin.math.max
import kotlin.math.min

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
    val contentSha256: String? = null
)

data class CollectionMigrationResult(
    val importedCount: Int,
    val failedCount: Int
)

object MovieCollectionStore {
    private const val DirectoryName = "movie-collection"
    private const val IndexFilename = "collection.json"
    private const val MigrationPreferences = "hanclip_movie_collection_migration"
    private const val LegacyMigrationCompletedKey = "export_history_v1_completed"
    private const val MigratedLegacyUrisKey = "export_history_v1_imported_uris"
    private const val SchemaVersion = 2
    private val collectionWriteLock = Any()

    fun list(context: Context): List<CollectedMovie> {
        val index = indexFile(context)
        if (!index.isFile) return emptyList()
        return runCatching {
            val root = JSONObject(index.readText())
            val items = root.optJSONArray("movies") ?: JSONArray()
            List(items.length()) { position -> items.getJSONObject(position).toCollectedMovie() }
                .filter { movie ->
                    videoFile(context, movie).isFile && videoFile(context, movie).canRead()
                }
                .sortedByDescending(CollectedMovie::createdAtMillis)
        }.getOrElse { emptyList() }
    }

    fun videoUri(context: Context, movie: CollectedMovie): Uri =
        Uri.fromFile(videoFile(context, movie))

    fun posterFile(context: Context, movie: CollectedMovie): File =
        File(collectionDirectory(context), movie.posterFilename)

    suspend fun importMovie(
        context: Context,
        sourceUri: Uri,
        title: String? = null,
        madeAtMillis: Long? = null,
        shootingStartAtMillis: Long? = null,
        shootingEndAtMillis: Long? = null,
        locationName: String? = null
    ): CollectedMovie = withContext(Dispatchers.IO) {
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

            try {
                val sourceHash = copySource(appContext, sourceUri, destination)
                val existingWithHashes = existing.map { movie ->
                    movie.takeIf { it.contentSha256 != null }
                        ?: movie.copy(contentSha256 = sha256(videoFile(appContext, movie)))
                }
                existingWithHashes.firstOrNull { it.contentSha256 == sourceHash }?.let { duplicate ->
                    destination.delete()
                    if (existingWithHashes != existing) save(appContext, existingWithHashes)
                    return@synchronized duplicate
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
                    contentSha256 = sourceHash
                )
                save(appContext, listOf(movie) + existingWithHashes)
                movie
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
        val updated = list(context).map { movie ->
            if (movie.id == movieId) movie.copy(title = normalized) else movie
        }
        save(context, updated)
    }

    fun remove(context: Context, movieId: String) {
        val movies = list(context)
        val target = movies.firstOrNull { it.id == movieId } ?: return
        videoFile(context, target).delete()
        posterFile(context, target).delete()
        save(context, movies.filterNot { it.id == movieId })
    }

    private fun save(context: Context, movies: List<CollectedMovie>) {
        val directory = collectionDirectory(context)
        val target = File(directory, IndexFilename)
        val temporary = File(directory, "$IndexFilename.tmp")
        val root = JSONObject()
            .put("schemaVersion", SchemaVersion)
            .put("movies", JSONArray().apply {
                movies.sortedByDescending(CollectedMovie::createdAtMillis).forEach { movie ->
                    put(movie.toJson())
                }
            })
        temporary.writeText(root.toString())
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

    private fun copySource(context: Context, sourceUri: Uri, destination: File): String {
        val input = when (sourceUri.scheme) {
            "file" -> sourceUri.path?.let(::File)?.inputStream()
            else -> context.contentResolver.openInputStream(sourceUri)
        } ?: error("선택한 동영상을 읽을 수 없습니다.")
        val digest = MessageDigest.getInstance("SHA-256")
        input.use { source ->
            java.security.DigestInputStream(source, digest).use { digestSource ->
                destination.outputStream().use(digestSource::copyTo)
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
            val candidates = listOf(
                min(max(durationSeconds * 0.12, 0.0), 2.0),
                min(max(durationSeconds * 0.03, 0.0), 0.5),
                0.0
            )
            val frame = candidates.firstNotNullOfOrNull { seconds ->
                runCatching {
                    retriever.getFrameAtTime(
                        (seconds * 1_000_000L).toLong(),
                        MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                    )
                }.getOrNull()
            } ?: return
            val scaled = frame.scaledToLongEdge(1080)
            target.outputStream().use { output ->
                scaled.compress(Bitmap.CompressFormat.JPEG, 84, output)
            }
            if (scaled !== frame) scaled.recycle()
            frame.recycle()
        } finally {
            retriever.release()
        }
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
        contentSha256 = optionalString("contentSha256")
    )

    private fun JSONObject.optionalString(key: String): String? =
        if (!has(key) || isNull(key)) null else optString(key, "")
            .takeIf(String::isNotBlank)
            ?.takeUnless { it.equals("null", ignoreCase = true) }

    private fun JSONObject.optionalLong(key: String): Long? =
        if (!has(key) || isNull(key)) null else optLong(key).takeIf { it > 0L }

    private fun JSONObject.putNullable(key: String, value: Any?): JSONObject =
        put(key, value ?: JSONObject.NULL)
}
