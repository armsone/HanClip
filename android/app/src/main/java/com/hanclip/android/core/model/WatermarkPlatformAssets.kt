package com.hanclip.android.core.model

import androidx.annotation.DrawableRes
import com.hanclip.android.R

@get:DrawableRes
val WatermarkPlatform.drawableResId: Int
    get() = when (this) {
        WatermarkPlatform.HanClip -> R.drawable.logo_mark
        WatermarkPlatform.Instagram -> R.drawable.copyright_instagram
        WatermarkPlatform.Facebook -> R.drawable.copyright_facebook
        WatermarkPlatform.YouTube -> R.drawable.copyright_youtube
        WatermarkPlatform.Blog -> R.drawable.copyright_blog
        WatermarkPlatform.KakaoTalk -> R.drawable.copyright_kakaotalk
        WatermarkPlatform.X -> R.drawable.copyright_x
        WatermarkPlatform.Phone -> R.drawable.copyright_telephone
        WatermarkPlatform.Homepage -> R.drawable.copyright_homepage
        WatermarkPlatform.Custom -> R.drawable.copyright_custom
    }
