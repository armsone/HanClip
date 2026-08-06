package com.hanclip.android.core.model

import kotlin.math.max
import kotlin.math.roundToInt

enum class OutputAspectRatio(
    val title: String,
    val width: Int,
    val height: Int
) {
    Square("정방형", 1080, 1080),
    Portrait3x4("세로 3:4", 1080, 1440),
    Landscape4x3("가로 4:3", 1440, 1080),
    Portrait9x16("세로 9:16", 1080, 1920),
    Landscape16x9("가로 16:9", 1920, 1080);

    companion object {
        fun automaticSize(sourceWidth: Int, sourceHeight: Int): Pair<Int, Int> {
            val safeWidth = max(1, sourceWidth)
            val safeHeight = max(1, sourceHeight)
            val ratio = safeWidth.toDouble() / safeHeight.toDouble()

            val rawWidth: Double
            val rawHeight: Double
            if (ratio >= 1.0) {
                if (ratio <= 16.0 / 9.0) {
                    rawWidth = 1080.0 * ratio
                    rawHeight = 1080.0
                } else {
                    rawWidth = 1920.0
                    rawHeight = 1920.0 / ratio
                }
            } else if (ratio >= 9.0 / 16.0) {
                rawWidth = 1080.0
                rawHeight = 1080.0 / ratio
            } else {
                rawWidth = 1920.0 * ratio
                rawHeight = 1920.0
            }

            return evenPixelValue(rawWidth) to evenPixelValue(rawHeight)
        }

        private fun evenPixelValue(value: Double): Int {
            val rounded = max(4, value.roundToInt())
            return max(4, rounded - rounded % 4)
        }
    }
}
