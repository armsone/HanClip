package com.hanclip.android.feature.aishot

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

@OptIn(UnstableApi::class)
internal object AiShotVideoTrimmer {
    fun pruneAbandonedBuffers(directory: File) {
        val abandonedBefore = System.currentTimeMillis() - 60_000L
        directory.listFiles()
            ?.filter {
                it.isFile &&
                    it.name.startsWith("aishot-buffer-") &&
                    it.lastModified() < abandonedBefore
            }
            ?.forEach { runCatching { it.delete() } }
    }

    suspend fun trimAroundTrigger(
        context: Context,
        sourceFile: File,
        destinationFile: File,
        triggerSeconds: Double,
        beforeSeconds: Double,
        afterSeconds: Double
    ): Uri = withContext(Dispatchers.Main.immediate) {
        val desiredDurationMs = ((beforeSeconds + afterSeconds) * 1000).toLong()
        val sourceDurationMs = readDurationMs(sourceFile)
        val requestedEndMs = ((triggerSeconds + afterSeconds).coerceAtLeast(0.5) * 1000).toLong()
        val endMs = requestedEndMs.coerceAtMost(sourceDurationMs)
        val requestedStartMs = ((triggerSeconds - beforeSeconds).coerceAtLeast(0.0) * 1000).toLong()
        val startMs = if (endMs - requestedStartMs < desiredDurationMs && sourceDurationMs >= desiredDurationMs) {
            (endMs - desiredDurationMs).coerceAtLeast(0L)
        } else {
            requestedStartMs
        }
        require(endMs > startMs) { "AiShot 저장 구간이 올바르지 않습니다." }
        destinationFile.parentFile?.mkdirs()
        if (destinationFile.exists()) destinationFile.delete()

        val mediaItem = MediaItem.Builder()
            .setUri(Uri.fromFile(sourceFile))
            .setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionMs(startMs)
                    .setEndPositionMs(endMs)
                    .setStartsAtKeyFrame(false)
                    .build()
            )
            .build()

        suspendCancellableCoroutine { continuation ->
            val transformer = Transformer.Builder(context.applicationContext)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(
                        composition: Composition,
                        exportResult: ExportResult
                    ) {
                        if (!continuation.isActive) return
                        if (destinationFile.length() > 0L) {
                            Log.i(
                                "HanClipAiShot",
                                "Trim complete: source=${sourceDurationMs}ms range=${startMs}..${endMs}ms output=${readDurationMs(destinationFile)}ms"
                            )
                            continuation.resume(Uri.fromFile(destinationFile))
                        } else {
                            continuation.resumeWithException(
                                IllegalStateException("AiShot 저장 영상이 비어 있습니다.")
                            )
                        }
                    }

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exportException: ExportException
                    ) {
                        destinationFile.delete()
                        if (continuation.isActive) {
                            continuation.resumeWithException(exportException)
                        }
                    }
                })
                .build()

            continuation.invokeOnCancellation {
                transformer.cancel()
                destinationFile.delete()
            }
            transformer.start(mediaItem, destinationFile.absolutePath)
        }
    }

    private fun readDurationMs(file: File): Long {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.absolutePath)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull()
                ?.coerceAtLeast(0L)
                ?: 0L
        } finally {
            retriever.release()
        }
    }
}
