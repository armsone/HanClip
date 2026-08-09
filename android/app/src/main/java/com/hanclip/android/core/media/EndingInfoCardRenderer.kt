package com.hanclip.android.core.media

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.net.Uri
import com.hanclip.android.core.model.ClipItem
import com.hanclip.android.core.model.EndingInfoCardTheme
import com.hanclip.android.core.model.WatermarkSettings
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.max

internal object EndingInfoCardRenderer {
    fun renderToFile(
        context: Context,
        clips: List<ClipItem>,
        width: Int,
        height: Int,
        settings: WatermarkSettings
    ): File? {
        if (!settings.includesEndingInfoCard) return null
        val located = clips.filter(ClipItem::hasUsableSourceLocation)
        if (located.isEmpty()) return null
        val bitmap = Bitmap.createBitmap(max(2, width), max(2, height), Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val theme = settings.endingInfoCardTheme
        val colors = colors(theme)
        drawBackground(context, canvas, bitmap, clips, theme, colors)
        drawCard(canvas, bitmap, located, settings, colors)
        val output = File(
            context.cacheDir,
            "ending-info/hanclip-ending-${System.currentTimeMillis()}.jpg"
        )
        output.parentFile?.mkdirs()
        return runCatching {
            output.outputStream().use { stream ->
                check(bitmap.compress(Bitmap.CompressFormat.JPEG, 94, stream))
            }
            output
        }.getOrNull().also { bitmap.recycle() }
    }

    private fun drawBackground(
        context: Context,
        canvas: Canvas,
        target: Bitmap,
        clips: List<ClipItem>,
        theme: EndingInfoCardTheme,
        colors: CardColors
    ) {
        val bounds = RectF(0f, 0f, target.width.toFloat(), target.height.toFloat())
        if (theme == EndingInfoCardTheme.Caption) {
            loadFirstThumbnail(context, clips)?.let { source ->
                val scale = max(
                    target.width.toFloat() / source.width,
                    target.height.toFloat() / source.height
                )
                val drawWidth = source.width * scale
                val drawHeight = source.height * scale
                val destination = RectF(
                    (target.width - drawWidth) / 2f,
                    (target.height - drawHeight) / 2f,
                    (target.width + drawWidth) / 2f,
                    (target.height + drawHeight) / 2f
                )
                canvas.drawBitmap(source, null, destination, Paint(Paint.ANTI_ALIAS_FLAG))
                source.recycle()
            }
            canvas.drawRect(bounds, Paint().apply { color = Color.argb(150, 0, 0, 0) })
        } else {
            canvas.drawRect(bounds, Paint().apply {
                shader = LinearGradient(
                    0f,
                    0f,
                    target.width.toFloat(),
                    target.height.toFloat(),
                    colors.backgroundStart,
                    colors.backgroundEnd,
                    Shader.TileMode.CLAMP
                )
            })
        }
    }

    private fun drawCard(
        canvas: Canvas,
        bitmap: Bitmap,
        clips: List<ClipItem>,
        settings: WatermarkSettings,
        colors: CardColors
    ) {
        val unit = minOf(bitmap.width, bitmap.height) / 100f
        val panel = RectF(
            bitmap.width * 0.09f,
            bitmap.height * 0.14f,
            bitmap.width * 0.91f,
            bitmap.height * 0.86f
        )
        canvas.drawRoundRect(panel, 4.5f * unit, 4.5f * unit, Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = colors.panel
        })

        val dates = clips.mapNotNull(ClipItem::sourceCreatedAtMillis)
        val dateText = dateRange(dates)
        val stops = clips
            .mapNotNull { clip ->
                clip.sourceLocationName?.takeIf(String::isNotBlank)?.let { location ->
                    location to clip.sourceCreatedAtMillis?.let(::shortDate).orEmpty()
                }
            }
            .distinctBy { it.first }
            .take(6)
        val heading = when (settings.endingInfoCardTheme) {
            EndingInfoCardTheme.Caption -> "여행의 기록"
            EndingInfoCardTheme.TreasureMap -> "TREASURE MAP"
            EndingInfoCardTheme.Itinerary -> "TRAVEL ITINERARY"
            EndingInfoCardTheme.Landmark -> "MEMORIES"
            EndingInfoCardTheme.Office -> "TRIP REPORT"
        }
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = colors.text
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            textSize = 5.6f * unit
        }
        canvas.drawText(heading, panel.centerX(), panel.top + 11f * unit, paint)
        paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
        paint.textSize = 3.2f * unit
        paint.color = colors.secondary
        canvas.drawText(dateText, panel.centerX(), panel.top + 17f * unit, paint)

        val routeTop = panel.top + 25f * unit
        val routeBottom = panel.bottom - 12f * unit
        val gap = (routeBottom - routeTop) / max(1, stops.size)
        val routeX = panel.left + 13f * unit
        if (stops.size > 1) {
            canvas.drawLine(
                routeX,
                routeTop,
                routeX,
                routeTop + gap * (stops.size - 1),
                Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = colors.secondary
                    strokeWidth = 0.8f * unit
                    pathEffect = android.graphics.DashPathEffect(floatArrayOf(1.5f * unit, 1.2f * unit), 0f)
                }
            )
        }
        stops.forEachIndexed { index, (location, stopDate) ->
            val y = routeTop + gap * index
            canvas.drawCircle(routeX, y, 2.3f * unit, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = colors.accent
            })
            paint.textAlign = Paint.Align.LEFT
            paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            paint.textSize = 3.8f * unit
            paint.color = colors.text
            canvas.drawText(location.take(24), routeX + 5f * unit, y + 0.8f * unit, paint)
            if (stopDate.isNotBlank()) {
                paint.textAlign = Paint.Align.RIGHT
                paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
                paint.textSize = 2.7f * unit
                paint.color = colors.secondary
                canvas.drawText(stopDate, panel.right - 6f * unit, y + 0.6f * unit, paint)
            }
        }

        if (settings.endingInfoCardTheme == EndingInfoCardTheme.TreasureMap) {
            val x = panel.right - (10 + settings.endingInfoCardVariation % 4 * 4) * unit
            val y = panel.bottom - 17f * unit
            val cross = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = colors.accent
                strokeWidth = 1.2f * unit
                strokeCap = Paint.Cap.ROUND
            }
            canvas.drawLine(x - 3f * unit, y - 3f * unit, x + 3f * unit, y + 3f * unit, cross)
            canvas.drawLine(x + 3f * unit, y - 3f * unit, x - 3f * unit, y + 3f * unit, cross)
        } else if (settings.endingInfoCardTheme == EndingInfoCardTheme.Landmark) {
            val roof = Path().apply {
                moveTo(panel.right - 24f * unit, panel.bottom - 8f * unit)
                lineTo(panel.right - 15f * unit, panel.bottom - 15f * unit)
                lineTo(panel.right - 6f * unit, panel.bottom - 8f * unit)
                close()
            }
            canvas.drawPath(roof, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = colors.secondary })
        }

        paint.textAlign = Paint.Align.CENTER
        paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        paint.textSize = 2.6f * unit
        paint.color = colors.accent
        canvas.drawText("HANCLIP", panel.centerX(), panel.bottom - 4.2f * unit, paint)
    }

    private fun loadFirstThumbnail(context: Context, clips: List<ClipItem>): Bitmap? {
        val uri = clips.firstNotNullOfOrNull { it.thumbnailUri ?: it.livePhotoStillUri }
            ?: return null
        return runCatching {
            when (uri.scheme) {
                "file" -> uri.path?.let(BitmapFactory::decodeFile)
                else -> context.contentResolver.openInputStream(uri)?.use(BitmapFactory::decodeStream)
            }
        }.getOrNull()
    }

    private fun dateRange(values: List<Long>): String {
        if (values.isEmpty()) return ""
        val formatter = SimpleDateFormat("yyyy. M. d.", Locale.KOREAN)
        val start = formatter.format(Date(values.minOrNull() ?: return ""))
        val end = formatter.format(Date(values.maxOrNull() ?: return start))
        return if (start == end) start else "$start  –  $end"
    }

    private fun shortDate(value: Long): String =
        SimpleDateFormat("M. d.", Locale.KOREAN).format(Date(value))

    private fun colors(theme: EndingInfoCardTheme): CardColors = when (theme) {
        EndingInfoCardTheme.Caption -> CardColors(
            Color.rgb(18, 22, 23), Color.rgb(34, 49, 47), Color.argb(150, 238, 246, 242),
            Color.WHITE, Color.rgb(222, 244, 236), Color.rgb(160, 205, 190)
        )
        EndingInfoCardTheme.TreasureMap -> CardColors(
            Color.rgb(122, 74, 31), Color.rgb(232, 194, 122), Color.argb(235, 242, 214, 156),
            Color.rgb(61, 31, 14), Color.rgb(122, 46, 15), Color.rgb(97, 64, 31)
        )
        EndingInfoCardTheme.Itinerary -> CardColors(
            Color.rgb(252, 245, 240), Color.rgb(255, 252, 250), Color.argb(245, 255, 255, 255),
            Color.rgb(56, 51, 54), Color.rgb(214, 71, 97), Color.rgb(240, 140, 125)
        )
        EndingInfoCardTheme.Landmark -> CardColors(
            Color.rgb(245, 230, 222), Color.rgb(255, 250, 240), Color.argb(247, 255, 247, 235),
            Color.rgb(69, 48, 43), Color.rgb(143, 74, 71), Color.rgb(176, 122, 107)
        )
        EndingInfoCardTheme.Office -> CardColors(
            Color.rgb(242, 242, 235), Color.WHITE, Color.argb(230, 255, 255, 255),
            Color.rgb(36, 41, 51), Color.rgb(33, 61, 102), Color.rgb(110, 122, 138)
        )
    }

    private data class CardColors(
        val backgroundStart: Int,
        val backgroundEnd: Int,
        val panel: Int,
        val text: Int,
        val accent: Int,
        val secondary: Int
    )
}
