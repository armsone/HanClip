package com.hanclip.android.core.media

import android.content.ContentValues
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import java.io.File
import java.io.InputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object VideoSaveShare {
    fun saveToGallery(context: Context, sourceUri: Uri, label: String? = null): Uri {
        val resolver = context.contentResolver
        val filename = newMovieFileName(label)
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, filename)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/HanClip")
                put(MediaStore.Video.Media.IS_PENDING, 1)
            } else {
                val moviesDirectory = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES),
                    "HanClip"
                ).apply { mkdirs() }
                put(MediaStore.Video.Media.DATA, File(moviesDirectory, filename).absolutePath)
            }
        }

        val targetUri = resolver.insert(
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
            values
        ) ?: error("갤러리 저장 위치를 만들 수 없습니다.")

        try {
            resolver.openOutputStream(targetUri)?.use { output ->
                context.openSourceInputStream(sourceUri).use { input ->
                    input.copyTo(output)
                }
            } ?: error("갤러리에 파일을 쓸 수 없습니다.")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                values.clear()
                values.put(MediaStore.Video.Media.IS_PENDING, 0)
                resolver.update(targetUri, values, null, null)
            }
        } catch (error: Throwable) {
            runCatching { resolver.delete(targetUri, null, null) }
            throw error
        }
        return targetUri
    }

    fun copyToUri(context: Context, sourceUri: Uri, targetUri: Uri) {
        context.contentResolver.openOutputStream(targetUri)?.use { output ->
            context.openSourceInputStream(sourceUri).use { input ->
                input.copyTo(output)
            }
        } ?: error("파일 저장 위치를 열 수 없습니다.")
    }

    fun shareVideo(context: Context, sourceUri: Uri) {
        val shareUri = if (sourceUri.scheme == "file") {
            FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                File(sourceUri.path.orEmpty())
            )
        } else {
            sourceUri
        }
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "video/mp4"
            putExtra(Intent.EXTRA_STREAM, shareUri)
            clipData = ClipData.newUri(context.contentResolver, "HanClip", shareUri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(
            Intent.createChooser(intent, "HanClip 공유")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    fun newMovieFileName(label: String? = null): String {
        val stamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.KOREAN).format(Date())
        val safeLabel = label
            ?.trim()
            ?.replace(Regex("[^\\p{L}\\p{N}_-]+"), "-")
            ?.trim('-')
            ?.takeIf { it.isNotBlank() }
        return listOfNotNull("HanClip", safeLabel, stamp).joinToString("-") + ".mp4"
    }
}

private fun Context.openSourceInputStream(sourceUri: Uri): InputStream {
    return runCatching { contentResolver.openInputStream(sourceUri) }
        .getOrNull()
        ?: File(sourceUri.path.orEmpty()).inputStream()
}
