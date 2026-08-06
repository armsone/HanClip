package com.hanclip.android.core.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val LightColors = lightColorScheme(
    primary = Color(0xFF0F8F61),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFE0F3EA),
    onPrimaryContainer = Color(0xFF063D29),
    secondary = Color(0xFF3D6F88),
    onSecondary = Color.White,
    tertiary = Color(0xFFE45D42),
    onTertiary = Color.White,
    background = Color(0xFFF7F8F6),
    onBackground = Color(0xFF14221A),
    surface = Color.White,
    onSurface = Color(0xFF14221A),
    surfaceVariant = Color(0xFFEAF0EC),
    onSurfaceVariant = Color(0xFF46534B),
    outline = Color(0xFF9AA89E)
)

@Composable
fun HanClipTheme(
    darkTheme: Boolean = false,
    content: @Composable () -> Unit
) {
    MaterialTheme(
        colorScheme = LightColors,
        content = content
    )
}
