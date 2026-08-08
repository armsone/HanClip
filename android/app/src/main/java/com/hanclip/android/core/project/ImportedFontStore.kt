package com.hanclip.android.core.project

import android.content.Context
import android.graphics.Typeface
import android.net.Uri
import android.provider.OpenableColumns
import java.io.File
import java.util.UUID

data class ImportedFontSummary(
    val id: String,
    val displayName: String
)

object ImportedFontStore {
    private const val DirectoryName = "imported-fonts"
    private const val IdPrefix = "imported_font:"
    private const val MaximumFontCount = 30

    fun list(context: Context): List<ImportedFontSummary> {
        return directory(context).listFiles()
            ?.filter { it.isFile && it.extension.lowercase() in setOf("ttf", "otf") }
            ?.sortedByDescending { it.lastModified() }
            ?.map { file ->
                ImportedFontSummary(
                    id = IdPrefix + file.name,
                    displayName = displayName(file.name)
                )
            }
            .orEmpty()
    }

    fun import(context: Context, uri: Uri): ImportedFontSummary {
        val sourceName = queryDisplayName(context, uri)
            ?: uri.lastPathSegment
            ?: "font.ttf"
        val extension = sourceName.substringAfterLast('.', "ttf").lowercase()
            .takeIf { it in setOf("ttf", "otf") }
            ?: "ttf"
        val baseName = sourceName.substringBeforeLast('.', sourceName)
            .replace(Regex("[^\\p{L}\\p{N}._ -]"), "_")
            .trim()
            .take(48)
            .ifBlank { "사용자 글꼴" }
        val target = File(
            directory(context),
            "$baseName--${UUID.randomUUID()}.$extension"
        )
        context.contentResolver.openInputStream(uri)?.use { input ->
            target.outputStream().use(input::copyTo)
        } ?: error("글꼴 파일을 열 수 없습니다.")
        runCatching { Typeface.createFromFile(target) }
            .onFailure {
                target.delete()
                throw IllegalArgumentException("TTF 또는 OTF 글꼴 파일이 아닙니다.", it)
            }
        prune(context)
        return ImportedFontSummary(
            id = IdPrefix + target.name,
            displayName = displayName(target.name)
        )
    }

    fun typeface(context: Context, id: String): Typeface? {
        val filename = id.takeIf { it.startsWith(IdPrefix) }
            ?.removePrefix(IdPrefix)
            ?: return null
        if (filename != File(filename).name) return null
        val file = File(directory(context), filename)
        if (!file.isFile) return null
        return runCatching { Typeface.createFromFile(file) }.getOrNull()
    }

    fun isImportedFont(id: String): Boolean = id.startsWith(IdPrefix)

    private fun directory(context: Context): File {
        return File(context.filesDir, DirectoryName).apply { mkdirs() }
    }

    private fun displayName(filename: String): String {
        return filename.substringBeforeLast('.')
            .substringBeforeLast("--")
            .ifBlank { "사용자 글꼴" }
    }

    private fun queryDisplayName(context: Context, uri: Uri): String? {
        return runCatching {
            context.contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        }.getOrNull()
    }

    private fun prune(context: Context) {
        directory(context).listFiles()
            ?.filter { it.isFile }
            ?.sortedByDescending { it.lastModified() }
            ?.drop(MaximumFontCount)
            ?.forEach { file -> runCatching { file.delete() } }
    }
}
