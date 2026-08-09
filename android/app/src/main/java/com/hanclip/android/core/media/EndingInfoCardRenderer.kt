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
import android.location.Location
import android.net.Uri
import com.hanclip.android.core.model.ClipItem
import com.hanclip.android.core.model.EndingInfoCardTheme
import com.hanclip.android.core.model.WatermarkSettings
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.sin
import kotlin.math.sqrt

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
        drawCard(context, canvas, bitmap, clips, settings, colors)
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
            canvas.drawColor(Color.BLACK)
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
                canvas.drawBitmap(source, null, destination, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    alpha = (0.46f * 255).toInt()
                })
                source.recycle()
            }
            canvas.drawRect(bounds, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = LinearGradient(
                    0f,
                    0f,
                    target.width.toFloat(),
                    target.height.toFloat(),
                    Color.argb((0.56f * 255).toInt(), 0, 0, 0),
                    (colors.secondary and 0x00FFFFFF) or ((0.48f * 255).toInt() shl 24),
                    Shader.TileMode.CLAMP
                )
            })
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
        val captionTypeface = when (settings.endingInfoCardTheme) {
            EndingInfoCardTheme.Caption -> CaptionTypefaceLoader.load(context, settings.fontName)
            EndingInfoCardTheme.TreasureMap -> CaptionTypefaceLoader.load(context, "gowun_batang")
            EndingInfoCardTheme.Landmark -> CaptionTypefaceLoader.load(context, "maruburi")
            else -> Typeface.DEFAULT
        }
        val unit = minOf(bitmap.width, bitmap.height) / 100f
        val panel = RectF(
            7.7f * unit,
            9.6f * unit,
            bitmap.width - 7.7f * unit,
            bitmap.height - 9.6f * unit
        )
        canvas.drawRoundRect(panel, 6.7f * unit, 6.7f * unit, Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = colors.panel
        })
        canvas.drawRoundRect(panel, 6.7f * unit, 6.7f * unit, Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            color = colors.secondary
            alpha = 158
            strokeWidth = max(1f, 0.31f * unit)
        })
        if (settings.endingInfoCardTheme == EndingInfoCardTheme.TreasureMap) {
            val inner = RectF(panel).apply { inset(3f * unit, 3f * unit) }
            canvas.drawRoundRect(inner, 3f * unit, 3f * unit, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                color = colors.accent
                alpha = 140
                strokeWidth = max(1f, 0.35f * unit)
                pathEffect = android.graphics.DashPathEffect(floatArrayOf(1.5f * unit, 1.2f * unit), 0f)
            })
            canvas.drawText(
                "✥",
                panel.right - 9f * unit,
                panel.top + 10f * unit,
                Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    textAlign = Paint.Align.CENTER
                    typeface = Typeface.create(Typeface.SERIF, Typeface.BOLD)
                    textSize = 6f * unit
                    color = colors.accent
                }
            )
        }

        val dates = clips.mapNotNull(ClipItem::sourceCreatedAtMillis)
        val dateText = dateRange(dates)
        val stops = endingStops(context, clips).take(8)
        val heading = when (settings.endingInfoCardTheme) {
            EndingInfoCardTheme.Caption -> "여행 기록"
            EndingInfoCardTheme.TreasureMap -> "여행 기록"
            EndingInfoCardTheme.Itinerary -> "여행 일정표"
            EndingInfoCardTheme.Landmark -> stops.firstOrNull()?.label?.let { first ->
                val last = stops.lastOrNull()?.label ?: first
                if (first == last) "$first 여행" else "$first · $last 여행"
            } ?: "여행 기록"
            EndingInfoCardTheme.Office -> ""
        }
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = colors.text
            textAlign = Paint.Align.LEFT
            typeface = Typeface.create(captionTypeface, Typeface.BOLD)
            textSize = 4.4f * unit
            if (settings.endingInfoCardTheme == EndingInfoCardTheme.Caption && settings.shadowEnabled) {
                setShadowLayer(
                    0.6f * unit,
                    0.15f * unit,
                    0.2f * unit,
                    colorWithOpacity(settings.shadowColorHex, settings.shadowOpacity)
                )
            }
        }
        if (settings.endingInfoCardTheme != EndingInfoCardTheme.Office) {
            paint.color = if (settings.endingInfoCardTheme == EndingInfoCardTheme.Caption) {
                colors.accent
            } else {
                colors.text
            }
            canvas.drawText(heading, panel.left + 6f * unit, panel.top + 9f * unit, paint)
            paint.typeface = Typeface.create(captionTypeface, Typeface.NORMAL)
            paint.textAlign = Paint.Align.CENTER
            paint.textSize = 5.8f * unit
            paint.color = if (settings.endingInfoCardTheme == EndingInfoCardTheme.Caption) {
                colors.accent
            } else {
                colors.secondary
            }
            canvas.drawText(dateText, panel.centerX(), panel.top + 17f * unit, paint)
        }

        when (settings.endingInfoCardTheme) {
            EndingInfoCardTheme.Itinerary -> {
                drawItinerary(canvas, panel, dateText, stops, colors, unit)
                return
            }
            EndingInfoCardTheme.Landmark -> {
                drawLandmarkJourney(canvas, panel, stops, colors, unit, captionTypeface)
                return
            }
            EndingInfoCardTheme.Office -> {
                drawOfficeReport(canvas, panel, dateText, stops, colors, unit)
                return
            }
            EndingInfoCardTheme.TreasureMap -> {
                drawTreasureMapRoute(
                    canvas = canvas,
                    panel = panel,
                    stops = stops,
                    variation = settings.endingInfoCardVariation,
                    colors = colors,
                    unit = unit,
                    typeface = captionTypeface
                )
                return
            }
            else -> Unit
        }
        drawCaptionRoute(canvas, panel, stops, colors, unit, captionTypeface, settings)
    }

    private fun drawCaptionRoute(
        canvas: Canvas,
        panel: RectF,
        stops: List<RouteStop>,
        colors: CardColors,
        unit: Float,
        typeface: Typeface,
        settings: WatermarkSettings
    ) {
        if (stops.isEmpty()) return
        val availableWidth = panel.width() - 16f * unit
        val routeTop = panel.top + 25f * unit
        val routeBottom = panel.bottom - 12f * unit
        val shadowColor = colorWithOpacity(settings.shadowColorHex, settings.shadowOpacity)
        var fontSize = 5.8f * unit
        val minimumSize = 1.6f * unit
        val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = colors.text
            textAlign = Paint.Align.LEFT
            this.typeface = Typeface.create(typeface, Typeface.BOLD)
            if (settings.shadowEnabled) {
                setShadowLayer(0.6f * unit, 0.15f * unit, 0.2f * unit, shadowColor)
            }
        }
        data class RouteToken(val index: Int, val width: Float)
        fun rowsAt(size: Float): List<List<RouteToken>> {
            labelPaint.textSize = size
            val rows = mutableListOf<MutableList<RouteToken>>()
            var current = mutableListOf<RouteToken>()
            var used = 0f
            stops.forEachIndexed { index, stop ->
                val transportWidth = if (index == 0) 0f else 7f * unit
                val tokenWidth = transportWidth + labelPaint.measureText(stop.label) + 2f * unit
                if (current.isNotEmpty() && used + tokenWidth > availableWidth) {
                    rows += current
                    current = mutableListOf()
                    used = 0f
                }
                current += RouteToken(index, tokenWidth)
                used += tokenWidth
            }
            if (current.isNotEmpty()) rows += current
            return rows
        }
        var rows = rowsAt(fontSize)
        while (fontSize > minimumSize && rows.size * fontSize * 1.9f > routeBottom - routeTop) {
            fontSize -= 0.35f * unit
            rows = rowsAt(fontSize)
        }
        labelPaint.textSize = fontSize
        val lineHeight = fontSize * 1.9f
        val totalHeight = rows.size * lineHeight
        var baseline = routeTop + (routeBottom - routeTop - totalHeight) / 2f - labelPaint.ascent()
        rows.forEach { row ->
            val rowWidth = row.sumOf { it.width.toDouble() }.toFloat()
            var x = panel.centerX() - rowWidth / 2f
            row.forEach { token ->
                if (token.index > 0) {
                    val previous = stops[token.index - 1]
                    drawTransportMark(
                        canvas,
                        x + 2.7f * unit,
                        baseline - fontSize * 0.36f,
                        previous.countryCode != stops[token.index].countryCode,
                        colors.secondary,
                        unit
                    )
                    x += 7f * unit
                }
                canvas.drawText(stops[token.index].label, x, baseline, labelPaint)
                x += labelPaint.measureText(stops[token.index].label) + 2f * unit
            }
            baseline += lineHeight
        }
    }

    private fun drawItinerary(
        canvas: Canvas,
        panel: RectF,
        dateText: String,
        stops: List<RouteStop>,
        colors: CardColors,
        unit: Float
    ) {
        canvas.drawRect(
            panel.left,
            panel.top,
            panel.right,
            panel.top + 20f * unit,
            Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(252, 232, 230) }
        )
        val headerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            color = colors.accent
            textSize = 5f * unit
        }
        canvas.drawText("여행 일정표", panel.centerX(), panel.top + 7.5f * unit, headerPaint)
        headerPaint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
        headerPaint.color = colors.secondary
        headerPaint.textSize = 1.9f * unit
        canvas.drawText("TRAVEL SCHEDULE", panel.centerX(), panel.top + 12f * unit, headerPaint)
        headerPaint.color = colors.text
        headerPaint.textSize = 2.4f * unit
        canvas.drawText(dateText, panel.centerX(), panel.top + 17f * unit, headerPaint)
        if (stops.isEmpty()) return
        val route = RectF(
            panel.left + 7f * unit,
            panel.top + 24f * unit,
            panel.right - 7f * unit,
            panel.bottom - 10f * unit
        )
        val columns = minOf(stops.size, if (route.width() > route.height() * 1.15f) 5 else 3)
        val rows = ceil(stops.size.toDouble() / max(1, columns)).toInt()
        val columnWidth = route.width() / max(1, columns)
        val rowHeight = route.height() / max(1, rows)
        val points = stops.indices.map { index ->
            val row = index / columns
            val position = index % columns
            val column = if (row % 2 == 0) position else columns - position - 1
            Pair(
                route.left + columnWidth * (column + 0.5f),
                route.top + rowHeight * (row + 0.45f)
            )
        }
        if (points.size > 1) {
            val path = Path().apply {
                moveTo(points.first().first, points.first().second)
                points.drop(1).forEach { lineTo(it.first, it.second) }
            }
            canvas.drawPath(path, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                color = colors.secondary
                alpha = 210
                strokeWidth = max(2f, minOf(3f * unit, rowHeight * 0.15f))
                strokeCap = Paint.Cap.ROUND
                strokeJoin = Paint.Join.ROUND
            })
        }
        val datePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            textAlign = Paint.Align.CENTER
            textSize = minOf(2.2f * unit, rowHeight * 0.15f)
        }
        val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = colors.text
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            textAlign = Paint.Align.CENTER
            textSize = minOf(2.8f * unit, rowHeight * 0.21f)
        }
        points.forEachIndexed { index, point ->
            val badgeWidth = minOf(9.5f * unit, columnWidth * 0.62f)
            val badgeHeight = minOf(4.1f * unit, rowHeight * 0.23f)
            val badge = RectF(
                point.first - badgeWidth / 2f,
                point.second - badgeHeight / 2f,
                point.first + badgeWidth / 2f,
                point.second + badgeHeight / 2f
            )
            canvas.drawRoundRect(badge, badgeHeight / 2f, badgeHeight / 2f, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = colors.accent
            })
            val baseline = badge.centerY() - (datePaint.ascent() + datePaint.descent()) / 2f
            canvas.drawText(stops[index].dateText.ifBlank { "–" }, badge.centerX(), baseline, datePaint)
            canvas.drawCircle(point.first, badge.top - 2.5f * unit, 1.5f * unit, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = colors.text
                alpha = 185
            })
            canvas.drawText(
                stops[index].label.take(24),
                point.first,
                badge.bottom + 3.4f * unit,
                labelPaint
            )
            if (index > 0 && stops[index - 1].countryCode != stops[index].countryCode) {
                val previous = points[index - 1]
                drawTransportMark(
                    canvas,
                    (previous.first + point.first) / 2f,
                    (previous.second + point.second) / 2f,
                    true,
                    colors.accent,
                    unit
                )
            }
        }
    }

    private fun drawTreasureMapRoute(
        canvas: Canvas,
        panel: RectF,
        stops: List<RouteStop>,
        variation: Int,
        colors: CardColors,
        unit: Float,
        typeface: Typeface
    ) {
        if (stops.isEmpty()) return
        val route = RectF(
            panel.left + 12f * unit,
            panel.top + 25f * unit,
            panel.right - 12f * unit,
            panel.bottom - 12f * unit
        )
        val count = stops.size
        val usableHeight = route.height() * 0.78f
        val top = route.top + route.height() * 0.10f
        val phase = (variation % 9) * 0.42f
        val direction = if (variation % 2 == 0) 1f else -1f
        val points = stops.indices.map { index ->
            val progress = if (count == 1) 0.5f else index.toFloat() / (count - 1)
            val wave = sin(progress * Math.PI.toFloat() * 2.4f - Math.PI.toFloat() / 2f + phase)
            Pair(
                route.centerX() + wave * route.width() * 0.28f * direction,
                top + progress * usableHeight
            )
        }
        val routePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            color = colors.secondary
            strokeWidth = max(1.4f, 0.58f * unit)
            strokeCap = Paint.Cap.ROUND
            pathEffect = android.graphics.DashPathEffect(floatArrayOf(1.2f * unit, 1.7f * unit), 0f)
        }
        points.zipWithNext().forEachIndexed { index, (start, end) ->
            val vertical = (end.second - start.second) * 0.50f
            canvas.drawPath(
                Path().apply {
                    moveTo(start.first, start.second)
                    cubicTo(
                        start.first,
                        start.second + vertical,
                        end.first,
                        end.second - vertical,
                        end.first,
                        end.second
                    )
                },
                routePaint
            )
            drawTransportMark(
                canvas,
                (start.first + end.first) / 2f,
                (start.second + end.second) / 2f,
                stops[index].countryCode != stops[index + 1].countryCode,
                colors.accent,
                unit
            )
        }
        val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = colors.text
            this.typeface = Typeface.create(typeface, Typeface.BOLD)
            textSize = max(2.1f * unit, minOf(3.8f * unit, 8.7f * unit / sqrt(count.toFloat())))
        }
        points.forEachIndexed { index, point ->
            val markerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = colors.accent
                strokeWidth = 0.9f * unit
                strokeCap = Paint.Cap.ROUND
            }
            if (index == 0) {
                val radius = 2.5f * unit
                canvas.drawLine(point.first - radius, point.second - radius, point.first + radius, point.second + radius, markerPaint)
                canvas.drawLine(point.first + radius, point.second - radius, point.first - radius, point.second + radius, markerPaint)
            } else {
                canvas.drawCircle(point.first, point.second, 1.7f * unit, markerPaint)
                canvas.drawCircle(point.first, point.second, 0.7f * unit, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = colors.panel })
            }
            val right = point.first <= route.centerX()
            labelPaint.textAlign = if (right) Paint.Align.LEFT else Paint.Align.RIGHT
            val labelX = point.first + if (right) 3f * unit else -3f * unit
            canvas.drawText(stops[index].label.take(24), labelX, point.second + 0.8f * unit, labelPaint)
        }
    }

    private fun drawLandmarkJourney(
        canvas: Canvas,
        panel: RectF,
        stops: List<RouteStop>,
        colors: CardColors,
        unit: Float,
        typeface: Typeface
    ) {
        if (stops.isEmpty()) return
        val border = RectF(panel).apply { inset(2.5f * unit, 2.5f * unit) }
        canvas.drawRoundRect(border, 4.6f * unit, 4.6f * unit, Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            color = colors.secondary
            alpha = 158
            strokeWidth = max(1f, 0.36f * unit)
        })
        val route = RectF(
            panel.left + 7.5f * unit,
            panel.top + 25f * unit,
            panel.right - 7.5f * unit,
            panel.bottom - 10f * unit
        )
        val columns = minOf(stops.size, if (route.width() > route.height() * 1.12f) 4 else 3)
        val rows = ceil(stops.size.toDouble() / max(1, columns)).toInt()
        val columnWidth = route.width() / max(1, columns)
        val rowHeight = route.height() / max(1, rows)
        val points = stops.indices.map { index ->
            val row = index / columns
            val position = index % columns
            val column = if (row % 2 == 0) position else columns - position - 1
            Pair(
                route.left + columnWidth * (column + 0.5f),
                route.top + rowHeight * (row + 0.48f)
            )
        }
        if (points.size > 1) {
            val path = Path().apply {
                moveTo(points.first().first, points.first().second)
                points.drop(1).forEach { lineTo(it.first, it.second) }
            }
            canvas.drawPath(path, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                color = colors.secondary
                alpha = 174
                strokeWidth = max(1.3f, 0.54f * unit)
                strokeCap = Paint.Cap.ROUND
                pathEffect = android.graphics.DashPathEffect(floatArrayOf(1f * unit, 1.4f * unit), 0f)
            })
        }
        points.forEachIndexed { index, point ->
            val landmark = landmarkDescriptor(stops[index].label)
            val iconSize = minOf(8.7f * unit, rowHeight * 0.38f, columnWidth * 0.42f)
            canvas.drawCircle(point.first, point.second - iconSize * 0.32f, iconSize * 0.64f, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.rgb(255, 247, 232)
            })
            canvas.drawText(
                landmark.emoji,
                point.first,
                point.second,
                Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    textAlign = Paint.Align.CENTER
                    textSize = iconSize
                    this.typeface = Typeface.DEFAULT
                }
            )
            val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = colors.text
                this.typeface = Typeface.create(typeface, Typeface.BOLD)
                textAlign = Paint.Align.CENTER
                textSize = minOf(2.7f * unit, rowHeight * 0.15f)
            }
            canvas.drawText(stops[index].label.take(20), point.first, point.second + iconSize * 0.75f, labelPaint)
            labelPaint.color = colors.secondary
            labelPaint.textSize = minOf(1.9f * unit, rowHeight * 0.105f)
            canvas.drawText(landmark.name, point.first, point.second + iconSize * 1.18f, labelPaint)
            canvas.drawCircle(point.first, point.second, 1.15f * unit, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = colors.accent
            })
        }
    }

    private data class LandmarkDescriptor(val name: String, val emoji: String)

    private fun landmarkDescriptor(label: String): LandmarkDescriptor {
        val value = label.lowercase(Locale.getDefault())
        val candidates = listOf(
            listOf("서울", "seoul") to LandmarkDescriptor("남산서울타워", "🗼"),
            listOf("제주", "jeju") to LandmarkDescriptor("한라산·성산일출봉", "🌋"),
            listOf("부산", "busan") to LandmarkDescriptor("광안대교·해동용궁사", "🌉"),
            listOf("인천", "incheon") to LandmarkDescriptor("인천대교·송도", "🌉"),
            listOf("경주", "gyeongju") to LandmarkDescriptor("불국사·첨성대", "🏯"),
            listOf("전주", "jeonju") to LandmarkDescriptor("전주한옥마을", "🏘️"),
            listOf("강릉", "gangneung") to LandmarkDescriptor("경포대", "🌊"),
            listOf("속초", "sokcho") to LandmarkDescriptor("설악산", "⛰️"),
            listOf("수원", "suwon") to LandmarkDescriptor("수원화성", "🏰"),
            listOf("여수", "yeosu") to LandmarkDescriptor("여수해상케이블카", "🚠"),
            listOf("안동", "andong") to LandmarkDescriptor("하회마을", "🏘️"),
            listOf("대구", "daegu") to LandmarkDescriptor("팔공산", "⛰️"),
            listOf("대전", "daejeon") to LandmarkDescriptor("엑스포과학공원", "🔭"),
            listOf("광주", "gwangju") to LandmarkDescriptor("국립아시아문화전당", "🏛️"),
            listOf("파리", "paris") to LandmarkDescriptor("Eiffel Tower", "🗼"),
            listOf("런던", "london") to LandmarkDescriptor("Big Ben·Tower Bridge", "🕰️"),
            listOf("뉴욕", "new york") to LandmarkDescriptor("Statue of Liberty", "🗽"),
            listOf("도쿄", "tokyo") to LandmarkDescriptor("Tokyo Tower·Sensoji", "🗼"),
            listOf("교토", "kyoto") to LandmarkDescriptor("Fushimi Inari", "⛩️"),
            listOf("오사카", "osaka") to LandmarkDescriptor("Osaka Castle", "🏯"),
            listOf("나라", "nara") to LandmarkDescriptor("Todaiji·Nara Park", "🦌"),
            listOf("삿포로", "sapporo") to LandmarkDescriptor("Sapporo Clock Tower", "❄️"),
            listOf("후쿠오카", "fukuoka") to LandmarkDescriptor("Fukuoka Tower", "🗼"),
            listOf("오키나와", "okinawa") to LandmarkDescriptor("Shurijo·Blue Cave", "🏝️"),
            listOf("로마", "rome", "roma") to LandmarkDescriptor("Colosseum", "🏛️"),
            listOf("베네치아", "venice", "venezia") to LandmarkDescriptor("Grand Canal", "🚤"),
            listOf("피렌체", "florence", "firenze") to LandmarkDescriptor("Florence Cathedral", "⛪"),
            listOf("바르셀로나", "barcelona") to LandmarkDescriptor("Sagrada Familia", "⛪"),
            listOf("마드리드", "madrid") to LandmarkDescriptor("Royal Palace", "🏰"),
            listOf("리스본", "lisbon") to LandmarkDescriptor("Belém Tower", "🚋"),
            listOf("암스테르담", "amsterdam") to LandmarkDescriptor("Canals·Windmills", "🚲"),
            listOf("베를린", "berlin") to LandmarkDescriptor("Brandenburg Gate", "🏛️"),
            listOf("프라하", "prague", "praha") to LandmarkDescriptor("Charles Bridge", "🏰"),
            listOf("비엔나", "vienna", "wien") to LandmarkDescriptor("Schönbrunn Palace", "🎼"),
            listOf("아테네", "athens") to LandmarkDescriptor("Acropolis", "🏛️"),
            listOf("이스탄불", "istanbul") to LandmarkDescriptor("Hagia Sophia", "🕌"),
            listOf("취리히", "zurich") to LandmarkDescriptor("Lake Zurich·Alps", "🏔️"),
            listOf("클락", "clark") to LandmarkDescriptor("Clark International Airport", "✈️"),
            listOf("마닐라", "manila") to LandmarkDescriptor("Intramuros", "🏰"),
            listOf("세부", "cebu") to LandmarkDescriptor("Magellan's Cross", "🏝️"),
            listOf("보라카이", "boracay") to LandmarkDescriptor("White Beach", "🏖️"),
            listOf("방콕", "bangkok") to LandmarkDescriptor("Grand Palace", "🛕"),
            listOf("푸껫", "phuket") to LandmarkDescriptor("Phang Nga Bay", "🏝️"),
            listOf("치앙마이", "chiang mai") to LandmarkDescriptor("Doi Suthep", "🛕"),
            listOf("싱가포르", "singapore") to LandmarkDescriptor("Marina Bay·Merlion", "🌆"),
            listOf("쿠알라룸푸르", "kuala lumpur") to LandmarkDescriptor("Petronas Towers", "🏙️"),
            listOf("발리", "bali") to LandmarkDescriptor("Uluwatu·Tanah Lot", "🏝️"),
            listOf("하노이", "hanoi") to LandmarkDescriptor("Hoan Kiem Lake", "🏯"),
            listOf("호찌민", "ho chi minh", "saigon") to LandmarkDescriptor("Central Post Office", "🏛️"),
            listOf("다낭", "da nang", "danang") to LandmarkDescriptor("Dragon Bridge", "🐉"),
            listOf("홍콩", "hong kong") to LandmarkDescriptor("Victoria Harbour", "🌃"),
            listOf("타이베이", "taipei") to LandmarkDescriptor("Taipei 101", "🏙️"),
            listOf("시드니", "sydney") to LandmarkDescriptor("Sydney Opera House", "🎭"),
            listOf("멜버른", "melbourne") to LandmarkDescriptor("Flinders Street", "🚋"),
            listOf("오클랜드", "auckland") to LandmarkDescriptor("Sky Tower", "🗼"),
            listOf("로스앤젤레스", "los angeles") to LandmarkDescriptor("Hollywood Sign", "🎬"),
            listOf("샌프란시스코", "san francisco") to LandmarkDescriptor("Golden Gate Bridge", "🌉"),
            listOf("라스베이거스", "las vegas") to LandmarkDescriptor("The Strip", "🎰"),
            listOf("워싱턴", "washington") to LandmarkDescriptor("U.S. Capitol", "🏛️"),
            listOf("시카고", "chicago") to LandmarkDescriptor("Cloud Gate", "🌆"),
            listOf("밴쿠버", "vancouver") to LandmarkDescriptor("Canada Place", "🏔️"),
            listOf("토론토", "toronto") to LandmarkDescriptor("CN Tower", "🗼"),
            listOf("리우", "rio de janeiro", "rio") to LandmarkDescriptor("Christ the Redeemer", "⛰️"),
            listOf("칸쿤", "cancun") to LandmarkDescriptor("Caribbean Beach", "🏖️"),
            listOf("두바이", "dubai") to LandmarkDescriptor("Burj Khalifa", "🏙️"),
            listOf("아부다비", "abu dhabi") to LandmarkDescriptor("Sheikh Zayed Mosque", "🕌"),
            listOf("카이로", "cairo") to LandmarkDescriptor("Pyramids of Giza", "🔺")
        )
        return candidates.firstOrNull { (keys, _) -> keys.any(value::contains) }?.second
            ?: LandmarkDescriptor("Local Landmark", "📍")
    }

    private fun drawOfficeReport(
        canvas: Canvas,
        panel: RectF,
        dateText: String,
        stops: List<RouteStop>,
        colors: CardColors,
        unit: Float
    ) {
        val content = RectF(panel).apply { inset(6.2f * unit, 5.1f * unit) }
        canvas.drawRect(
            content.left,
            content.top,
            content.left + 1.3f * unit,
            content.top + 12.3f * unit,
            Paint().apply { color = colors.accent }
        )
        val headerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = colors.accent
            typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
            textSize = 4.9f * unit
            textAlign = Paint.Align.LEFT
        }
        canvas.drawText("여행 기록 보고서", content.left + 3.6f * unit, content.top + 5.6f * unit, headerPaint)
        headerPaint.textSize = 1.8f * unit
        headerPaint.color = colors.secondary
        canvas.drawText("HANCLIP TRAVEL REPORT", content.left + 3.6f * unit, content.top + 10.2f * unit, headerPaint)
        headerPaint.textAlign = Paint.Align.RIGHT
        canvas.drawText(
            "DOCUMENT  #${kotlin.math.abs(dateText.hashCode()) % 100_000}",
            content.right,
            content.top + 4.1f * unit,
            headerPaint
        )
        val bodyPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = colors.text
            typeface = Typeface.create(Typeface.MONOSPACE, Typeface.NORMAL)
            textSize = 2.05f * unit
            textAlign = Paint.Align.RIGHT
        }
        canvas.drawText("PERIOD  $dateText", content.right, content.top + 9f * unit, bodyPaint)

        val summaryTop = content.top + 14.9f * unit
        val summaryHeight = 7.7f * unit
        canvas.drawRect(content.left, summaryTop, content.right, summaryTop + summaryHeight, Paint().apply {
            color = colors.accent
            alpha = 20
        })
        bodyPaint.textAlign = Paint.Align.LEFT
        bodyPaint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        bodyPaint.textSize = 2.3f * unit
        bodyPaint.color = colors.accent
        canvas.drawText("방문 지역  ${stops.size}곳", content.left + 2.6f * unit, summaryTop + 5f * unit, bodyPaint)
        bodyPaint.textAlign = Paint.Align.RIGHT
        bodyPaint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
        bodyPaint.textSize = 2.05f * unit
        bodyPaint.color = colors.secondary
        canvas.drawText("작성  HANCLIP", content.right - 2.6f * unit, summaryTop + 5f * unit, bodyPaint)

        val tableTop = summaryTop + 10.8f * unit
        val tableBottom = content.bottom
        val headerHeight = minOf(5.65f * unit, (tableBottom - tableTop) * 0.13f)
        val numberWidth = content.width() * 0.10f
        val dateWidth = content.width() * 0.22f
        val transferWidth = content.width() * 0.18f
        val columns = floatArrayOf(
            content.left,
            content.left + numberWidth,
            content.left + numberWidth + dateWidth,
            content.right - transferWidth,
            content.right
        )
        canvas.drawRect(content.left, tableTop, content.right, tableTop + headerHeight, Paint().apply {
            color = colors.accent
        })
        val headers = arrayOf("NO.", "DATE", "REGION", "MOVE")
        bodyPaint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        bodyPaint.textSize = minOf(1.9f * unit, headerHeight * 0.45f)
        bodyPaint.color = Color.WHITE
        headers.forEachIndexed { index, value ->
            bodyPaint.textAlign = if (index == 2) Paint.Align.LEFT else Paint.Align.CENTER
            val x = if (index == 2) columns[index] + 1f * unit else (columns[index] + columns[index + 1]) / 2f
            val baseline = tableTop + headerHeight / 2f - (bodyPaint.ascent() + bodyPaint.descent()) / 2f
            canvas.drawText(value, x, baseline, bodyPaint)
        }
        val rowHeight = (tableBottom - tableTop - headerHeight) / max(1, stops.size)
        stops.forEachIndexed { index, stop ->
            val top = tableTop + headerHeight + rowHeight * index
            if (index % 2 == 0) {
                canvas.drawRect(content.left, top, content.right, top + rowHeight, Paint().apply {
                    color = colors.secondary
                    alpha = 18
                })
            }
            canvas.drawRect(content.left, top, content.right, top + rowHeight, Paint().apply {
                style = Paint.Style.STROKE
                color = colors.secondary
                alpha = 56
                strokeWidth = max(1f, 0.18f * unit)
            })
            val values = arrayOf(
                String.format(Locale.US, "%02d", index + 1),
                stop.dateText.ifBlank { "–" },
                stop.label.take(28),
                if (index == 0) "시작" else if (stops[index - 1].countryCode == stop.countryCode) "차량" else "항공"
            )
            bodyPaint.textSize = minOf(2.4f * unit, rowHeight * 0.32f)
            val baseline = top + rowHeight / 2f - (bodyPaint.ascent() + bodyPaint.descent()) / 2f
            values.forEachIndexed { column, value ->
                bodyPaint.textAlign = if (column == 2) Paint.Align.LEFT else Paint.Align.CENTER
                bodyPaint.typeface = Typeface.create(
                    if (column == 2) Typeface.DEFAULT else Typeface.MONOSPACE,
                    if (column == 2) Typeface.BOLD else Typeface.NORMAL
                )
                bodyPaint.color = if (column == 2) colors.text else colors.secondary
                val x = if (column == 2) columns[column] + 1f * unit else (columns[column] + columns[column + 1]) / 2f
                canvas.drawText(value, x, baseline, bodyPaint)
            }
        }
    }

    private data class RouteStop(
        val countryCode: String,
        val label: String,
        val dateText: String,
        val dayKey: String
    )

    private data class RoutePlace(
        val countryCode: String,
        val countryName: String?,
        val cityName: String
    )

    private fun endingStops(context: Context, clips: List<ClipItem>): List<RouteStop> {
        val result = mutableListOf<RouteStop>()
        val fallbackDate = clips.mapNotNull(ClipItem::sourceCreatedAtMillis).minOrNull()
        var previousLatitude: Double? = null
        var previousLongitude: Double? = null
        clips.forEach { clip ->
            val rawLabel = clip.sourceLocationName?.trim().orEmpty()
            if (rawLabel.isEmpty()) return@forEach
            val date = clip.sourceCreatedAtMillis ?: fallbackDate
            val currentDay = date?.let(::dayKey).orEmpty()
            val latitude = clip.sourceLatitude
            val longitude = clip.sourceLongitude
            if (latitude != null && longitude != null &&
                previousLatitude != null && previousLongitude != null &&
                result.lastOrNull()?.dayKey == currentDay
            ) {
                val distance = FloatArray(1)
                Location.distanceBetween(
                    previousLatitude,
                    previousLongitude,
                    latitude,
                    longitude,
                    distance
                )
                if (distance[0] < 5_000f) return@forEach
            }
            val place = routePlace(context, clip, rawLabel)
            val previous = result.lastOrNull()
            val label = when {
                place.countryCode == "KR" -> place.cityName
                previous?.countryCode != place.countryCode && !place.countryName.isNullOrBlank() ->
                    "${place.countryName} ${place.cityName}".trim()
                else -> place.cityName
            }
            val stop = RouteStop(
                countryCode = place.countryCode,
                label = label,
                dateText = date?.let(::shortDate).orEmpty(),
                dayKey = currentDay
            )
            if (previous?.countryCode == stop.countryCode &&
                previous.label == stop.label &&
                previous.dayKey == stop.dayKey
            ) return@forEach
            result += stop
            previousLatitude = latitude
            previousLongitude = longitude
        }
        return result
    }

    @Suppress("DEPRECATION")
    private fun routePlace(context: Context, clip: ClipItem, fallbackLabel: String): RoutePlace {
        val latitude = clip.sourceLatitude
        val longitude = clip.sourceLongitude
        if (latitude != null && longitude != null) {
            runCatching {
                Geocoder(context, Locale.KOREAN)
                    .getFromLocation(latitude, longitude, 1)
                    ?.firstOrNull()
            }.getOrNull()?.let { address ->
                val code = address.countryCode?.uppercase(Locale.US).orEmpty()
                val city = address.locality ?: address.subAdminArea ?: address.adminArea
                if (code.isNotBlank() && !city.isNullOrBlank()) {
                    return RoutePlace(code, address.countryName, city)
                }
            }
            if (latitude in 33.0..39.5 && longitude in 124.0..132.0) {
                return RoutePlace("KR", "대한민국", fallbackLabel)
            }
        }
        val fallbackCode = if (latitude == null || longitude == null) {
            if (fallbackLabel.any { it.code in 0xAC00..0xD7A3 }) "KR" else "ZZ"
        } else {
            "ZZ"
        }
        return RoutePlace(fallbackCode, null, fallbackLabel)
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
            Color.rgb(18, 22, 23), Color.rgb(34, 49, 47), Color.argb(97, 238, 246, 242),
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

    private fun colorWithOpacity(value: String, opacity: Double): Int {
        val color = safeColor(value, Color.BLACK)
        val alpha = (opacity.coerceIn(0.0, 1.0) * 255).toInt()
        return (color and 0x00FFFFFF) or (alpha shl 24)
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
