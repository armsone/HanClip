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
import android.location.Geocoder
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
        val colors = colors(theme, settings)
        drawBackground(context, canvas, bitmap, clips, theme, colors)
        drawCard(context, canvas, bitmap, located, settings, colors)
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
        context: Context,
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
        val stops = endingStops(context, clips).take(8)
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

        when (settings.endingInfoCardTheme) {
            EndingInfoCardTheme.Itinerary -> {
                drawItinerary(canvas, panel, stops, colors, unit)
                drawFooter(canvas, panel, colors, unit)
                return
            }
            EndingInfoCardTheme.Landmark -> {
                drawLandmarkJourney(canvas, panel, stops, colors, unit)
                drawFooter(canvas, panel, colors, unit)
                return
            }
            EndingInfoCardTheme.Office -> {
                drawOfficeReport(canvas, panel, dateText, stops, colors, unit)
                return
            }
            else -> Unit
        }

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
        stops.forEachIndexed { index, stop ->
            val y = routeTop + gap * index
            if (index > 0) {
                drawTransportMark(
                    canvas = canvas,
                    centerX = routeX,
                    centerY = y - gap / 2f,
                    flies = stops[index - 1].countryCode != stop.countryCode,
                    color = colors.secondary,
                    unit = unit
                )
            }
            canvas.drawCircle(routeX, y, 2.3f * unit, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = colors.accent
            })
            paint.textAlign = Paint.Align.LEFT
            paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            paint.textSize = 3.8f * unit
            paint.color = colors.text
            canvas.drawText(stop.label.take(28), routeX + 5f * unit, y + 0.8f * unit, paint)
            if (stop.dateText.isNotBlank()) {
                paint.textAlign = Paint.Align.RIGHT
                paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
                paint.textSize = 2.7f * unit
                paint.color = colors.secondary
                canvas.drawText(stop.dateText, panel.right - 6f * unit, y + 0.6f * unit, paint)
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

        drawFooter(canvas, panel, colors, unit)
    }

    private fun drawItinerary(
        canvas: Canvas,
        panel: RectF,
        stops: List<RouteStop>,
        colors: CardColors,
        unit: Float
    ) {
        val top = panel.top + 24f * unit
        val bottom = panel.bottom - 10f * unit
        val rowHeight = (bottom - top) / max(1, stops.size)
        val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = colors.secondary
            strokeWidth = max(1f, 0.25f * unit)
        }
        val datePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = colors.accent
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            textSize = 3.0f * unit
            textAlign = Paint.Align.LEFT
        }
        val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = colors.text
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            textSize = 3.8f * unit
            textAlign = Paint.Align.LEFT
        }
        stops.forEachIndexed { index, stop ->
            val y = top + rowHeight * index
            canvas.drawLine(panel.left + 6f * unit, y + rowHeight * 0.72f, panel.right - 6f * unit, y + rowHeight * 0.72f, linePaint)
            canvas.drawText(stop.dateText.ifBlank { "–" }, panel.left + 7f * unit, y + 3.2f * unit, datePaint)
            canvas.drawText(stop.label.take(30), panel.left + 24f * unit, y + 3.2f * unit, labelPaint)
            if (index > 0) {
                drawTransportMark(
                    canvas,
                    panel.right - 9f * unit,
                    y + 1.5f * unit,
                    stops[index - 1].countryCode != stop.countryCode,
                    colors.secondary,
                    unit
                )
            }
        }
    }

    private fun drawLandmarkJourney(
        canvas: Canvas,
        panel: RectF,
        stops: List<RouteStop>,
        colors: CardColors,
        unit: Float
    ) {
        val visible = stops.take(4)
        val top = panel.top + 25f * unit
        val cellGap = 3f * unit
        val cellWidth = (panel.width() - 15f * unit) / 2f
        val cellHeight = (panel.bottom - top - 12f * unit) / 2f
        visible.forEachIndexed { index, stop ->
            val column = index % 2
            val row = index / 2
            val left = panel.left + 5f * unit + column * (cellWidth + cellGap)
            val card = RectF(left, top + row * (cellHeight + cellGap), left + cellWidth, top + row * (cellHeight + cellGap) + cellHeight)
            canvas.drawRoundRect(card, 2.5f * unit, 2.5f * unit, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.argb(105, Color.red(colors.accent), Color.green(colors.accent), Color.blue(colors.accent))
            })
            val skyline = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = colors.secondary }
            val baseline = card.top + cellHeight * 0.48f
            repeat(4) { tower ->
                val towerWidth = cellWidth / 10f
                val towerLeft = card.left + 4f * unit + tower * (towerWidth + 1.2f * unit)
                val height = (4 + (tower + index) % 4 * 2) * unit
                canvas.drawRect(towerLeft, baseline - height, towerLeft + towerWidth, baseline, skyline)
            }
            val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = colors.text
                typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
                textAlign = Paint.Align.CENTER
                textSize = 3.1f * unit
            }
            canvas.drawText(stop.label.take(20), card.centerX(), card.bottom - 5f * unit, labelPaint)
            labelPaint.color = colors.accent
            labelPaint.textSize = 2.3f * unit
            canvas.drawText(stop.dateText, card.centerX(), card.bottom - 2f * unit, labelPaint)
        }
    }

    private fun drawOfficeReport(
        canvas: Canvas,
        panel: RectF,
        dateText: String,
        stops: List<RouteStop>,
        colors: CardColors,
        unit: Float
    ) {
        canvas.drawRect(panel.left, panel.top, panel.left + 2f * unit, panel.bottom, Paint().apply { color = colors.accent })
        val headerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = colors.accent
            typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
            textSize = 2.7f * unit
            textAlign = Paint.Align.LEFT
        }
        canvas.drawText("HANCLIP / TRIP REPORT", panel.left + 7f * unit, panel.top + 8f * unit, headerPaint)
        headerPaint.textAlign = Paint.Align.RIGHT
        canvas.drawText("NO. ${dateText.filter(Char::isDigit).takeLast(6).ifBlank { "000001" }}", panel.right - 6f * unit, panel.top + 8f * unit, headerPaint)
        val bodyPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = colors.text
            typeface = Typeface.create(Typeface.MONOSPACE, Typeface.NORMAL)
            textSize = 2.7f * unit
            textAlign = Paint.Align.LEFT
        }
        canvas.drawText("촬영기간  $dateText", panel.left + 7f * unit, panel.top + 16f * unit, bodyPaint)
        val top = panel.top + 23f * unit
        val rowHeight = (panel.bottom - top - 9f * unit) / max(1, stops.size)
        stops.forEachIndexed { index, stop ->
            val y = top + rowHeight * index
            canvas.drawLine(panel.left + 6f * unit, y + rowHeight * 0.70f, panel.right - 6f * unit, y + rowHeight * 0.70f, Paint().apply {
                color = colors.secondary
                strokeWidth = max(1f, 0.22f * unit)
            })
            bodyPaint.typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
            canvas.drawText(stop.dateText.ifBlank { "–" }, panel.left + 7f * unit, y + 3f * unit, bodyPaint)
            bodyPaint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            canvas.drawText(stop.label.take(30), panel.left + 24f * unit, y + 3f * unit, bodyPaint)
            if (index > 0) {
                val movement = if (stops[index - 1].countryCode == stop.countryCode) "차량" else "항공"
                bodyPaint.textAlign = Paint.Align.RIGHT
                bodyPaint.typeface = Typeface.create(Typeface.MONOSPACE, Typeface.NORMAL)
                canvas.drawText(movement, panel.right - 7f * unit, y + 3f * unit, bodyPaint)
                bodyPaint.textAlign = Paint.Align.LEFT
            }
        }
        drawFooter(canvas, panel, colors, unit)
    }

    private fun drawFooter(canvas: Canvas, panel: RectF, colors: CardColors, unit: Float) {
        canvas.drawText(
            "HANCLIP",
            panel.centerX(),
            panel.bottom - 4.2f * unit,
            Paint(Paint.ANTI_ALIAS_FLAG).apply {
                textAlign = Paint.Align.CENTER
                typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
                textSize = 2.6f * unit
                color = colors.accent
            }
        )
    }

    private data class RouteStop(
        val countryCode: String,
        val label: String,
        val dateText: String,
        val dayKey: String
    )

    private fun endingStops(context: Context, clips: List<ClipItem>): List<RouteStop> {
        val result = mutableListOf<RouteStop>()
        clips.forEach { clip ->
            val rawLabel = clip.sourceLocationName?.trim().orEmpty()
            if (rawLabel.isEmpty()) return@forEach
            val date = clip.sourceCreatedAtMillis
            val countryCode = countryCode(context, clip)
            val stop = RouteStop(
                countryCode = countryCode,
                label = rawLabel,
                dateText = date?.let(::shortDate).orEmpty(),
                dayKey = date?.let(::dayKey).orEmpty()
            )
            val previous = result.lastOrNull()
            if (previous?.countryCode == stop.countryCode &&
                previous.label == stop.label &&
                previous.dayKey == stop.dayKey
            ) return@forEach
            result += stop
        }
        return result
    }

    @Suppress("DEPRECATION")
    private fun countryCode(context: Context, clip: ClipItem): String {
        val latitude = clip.sourceLatitude
        val longitude = clip.sourceLongitude
        if (latitude != null && longitude != null) {
            runCatching {
                Geocoder(context, Locale.ENGLISH)
                    .getFromLocation(latitude, longitude, 1)
                    ?.firstOrNull()
                    ?.countryCode
                    ?.uppercase(Locale.US)
            }.getOrNull()?.takeIf(String::isNotBlank)?.let { return it }
            if (latitude in 33.0..39.5 && longitude in 124.0..132.0) return "KR"
        }
        return if (clip.sourceLocationName.orEmpty().any { it.code in 0xAC00..0xD7A3 }) "KR" else "ZZ"
    }

    private fun dayKey(value: Long): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(value))

    private fun drawTransportMark(
        canvas: Canvas,
        centerX: Float,
        centerY: Float,
        flies: Boolean,
        color: Int,
        unit: Float
    ) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            strokeWidth = max(1f, 0.7f * unit)
            strokeCap = Paint.Cap.ROUND
            style = Paint.Style.STROKE
        }
        if (flies) {
            val wing = 2.0f * unit
            canvas.drawLine(centerX, centerY - wing, centerX, centerY + wing, paint)
            canvas.drawLine(centerX - wing, centerY, centerX + wing, centerY, paint)
            canvas.drawLine(centerX, centerY + wing, centerX - unit, centerY + 3f * unit, paint)
            canvas.drawLine(centerX, centerY + wing, centerX + unit, centerY + 3f * unit, paint)
        } else {
            val body = RectF(
                centerX - 2.4f * unit,
                centerY - 1.3f * unit,
                centerX + 2.4f * unit,
                centerY + 1.1f * unit
            )
            canvas.drawRoundRect(body, 0.7f * unit, 0.7f * unit, paint)
            canvas.drawCircle(centerX - 1.4f * unit, centerY + 1.5f * unit, 0.55f * unit, paint)
            canvas.drawCircle(centerX + 1.4f * unit, centerY + 1.5f * unit, 0.55f * unit, paint)
        }
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

    private fun colors(theme: EndingInfoCardTheme, settings: WatermarkSettings): CardColors = when (theme) {
        EndingInfoCardTheme.Caption -> CardColors(
            Color.rgb(18, 22, 23), Color.rgb(34, 49, 47), Color.argb(150, 238, 246, 242),
            safeColor(settings.textColorHex, Color.WHITE),
            safeColor(settings.textColorHex, Color.rgb(222, 244, 236)),
            safeColor(settings.shadowColorHex, Color.rgb(160, 205, 190))
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

    private fun safeColor(value: String, fallback: Int): Int =
        runCatching { Color.parseColor(value) }.getOrDefault(fallback)

    private data class CardColors(
        val backgroundStart: Int,
        val backgroundEnd: Int,
        val panel: Int,
        val text: Int,
        val accent: Int,
        val secondary: Int
    )
}
