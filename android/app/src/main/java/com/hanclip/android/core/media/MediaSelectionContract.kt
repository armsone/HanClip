package com.hanclip.android.core.media

import android.content.Context
import android.content.Intent
import android.net.Uri

data class MediaSelectionBatch(
    val uris: List<Uri>,
    val duplicateSelectionCount: Int
)

object MediaSelectionContract {
    fun normalize(uris: List<Uri>): MediaSelectionBatch {
        val ordered = uris.filter { it != Uri.EMPTY }
        val unique = ordered.distinctBy(Uri::toString)
        return MediaSelectionBatch(
            uris = unique,
            duplicateSelectionCount = ordered.size - unique.size
        )
    }

    fun fromResultIntent(context: Context, intent: Intent?): MediaSelectionBatch {
        if (intent == null) return MediaSelectionBatch(emptyList(), 0)
        val selected = buildList {
            intent.clipData?.let { clipData ->
                for (index in 0 until clipData.itemCount) {
                    clipData.getItemAt(index).uri?.let(::add)
                }
            }
            intent.data?.let(::add)
        }
        val normalized = normalize(selected)
        val persistFlags = intent.flags and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        if (persistFlags != 0) {
            normalized.uris.forEach { uri ->
                runCatching {
                    context.contentResolver.takePersistableUriPermission(uri, persistFlags)
                }
            }
        }
        return normalized
    }
}
