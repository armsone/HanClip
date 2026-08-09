package com.hanclip.android.feature.editor

import android.view.WindowManager
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Undo
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.DialogWindowProvider
import androidx.core.view.WindowCompat
import com.hanclip.android.core.theme.HanClipPalette

@Composable
internal fun FullScreenDialogSystemBars(
    background: Color,
    navigationBackground: Color = background
) {
    val view = LocalView.current
    DisposableEffect(view, background, navigationBackground) {
        val window = ((view as? DialogWindowProvider)
            ?: (view.parent as? DialogWindowProvider))?.window
        if (window == null) {
            onDispose { }
        } else {
            val oldStatusColor = window.statusBarColor
            val oldNavigationColor = window.navigationBarColor
            val oldDecorBackground = window.decorView.background
            val hadDimBehind = window.attributes.flags and
                WindowManager.LayoutParams.FLAG_DIM_BEHIND != 0
            val controller = WindowCompat.getInsetsController(window, view)
            val oldLightStatusBars = controller.isAppearanceLightStatusBars
            val oldLightNavigationBars = controller.isAppearanceLightNavigationBars
            window.statusBarColor = background.toArgb()
            window.navigationBarColor = navigationBackground.toArgb()
            window.decorView.setBackgroundColor(background.toArgb())
            window.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
            controller.isAppearanceLightStatusBars = background.luminance() > 0.5f
            controller.isAppearanceLightNavigationBars = navigationBackground.luminance() > 0.5f
            onDispose {
                window.statusBarColor = oldStatusColor
                window.navigationBarColor = oldNavigationColor
                window.decorView.background = oldDecorBackground
                if (hadDimBehind) {
                    window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
                }
                controller.isAppearanceLightStatusBars = oldLightStatusBars
                controller.isAppearanceLightNavigationBars = oldLightNavigationBars
            }
        }
    }
}

@Composable
internal fun FullScreenSettingsHeader(
    title: String,
    titleIcon: ImageVector,
    resetDescription: String,
    palette: HanClipPalette,
    onReset: () -> Unit,
    onDismiss: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        SettingsHeaderCircleButton(
            icon = Icons.AutoMirrored.Outlined.Undo,
            description = resetDescription,
            palette = palette,
            onClick = onReset
        )
        Spacer(Modifier.weight(1f))
        SettingsHeaderCircleButton(
            icon = Icons.Outlined.Close,
            description = "닫기",
            palette = palette,
            onClick = onDismiss
        )
    }
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.End,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Surface(
            modifier = Modifier.size(30.dp),
            shape = RoundedCornerShape(10.dp),
            color = palette.secondary.copy(alpha = 0.14f)
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(titleIcon, contentDescription = null, tint = palette.primary, modifier = Modifier.size(17.dp))
            }
        }
        Spacer(Modifier.size(8.dp))
        Text(
            title,
            color = palette.text.copy(alpha = 0.78f),
            fontSize = 16.sp,
            fontWeight = FontWeight.Black
        )
    }
}

@Composable
private fun SettingsHeaderCircleButton(
    icon: ImageVector,
    description: String,
    palette: HanClipPalette,
    onClick: () -> Unit
) {
    Surface(
        modifier = Modifier.size(52.dp),
        shape = RoundedCornerShape(26.dp),
        color = palette.solidPanel,
        border = BorderStroke(1.dp, palette.border),
        onClick = onClick
    ) {
        Box(contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = description, tint = palette.primary, modifier = Modifier.size(27.dp))
        }
    }
}
