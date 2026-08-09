package com.hanclip.android.core.media

import android.content.Context
import android.graphics.Typeface
import com.hanclip.android.core.project.ImportedFontStore

internal object CaptionTypefaceLoader {
    fun load(context: Context, fontName: String): Typeface {
        ImportedFontStore.typeface(context, fontName)?.let { return it }
        val assetPath = when (fontName) {
            "pretendard_bold" -> "fonts/pretendard_bold.ttf"
            "kakao_big_sans" -> "fonts/kakao_big_sans_regular.ttf"
            "gowun_batang" -> "fonts/gowun_batang_regular.ttf"
            "gowun_dodum" -> "fonts/gowun_dodum_regular.ttf"
            "nanum_gothic" -> "fonts/nanum_gothic_regular.ttf"
            "cafe24_ssurround" -> "fonts/cafe24_ssurround.ttf"
            "puradak_gentle_gothic" -> "fonts/puradak_gentle_gothic.ttf"
            "tenada" -> "fonts/tenada.ttf"
            "do_hyeon" -> "fonts/do_hyeon_regular.ttf"
            "black_han_sans" -> "fonts/black_han_sans_regular.ttf"
            "maruburi" -> "fonts/maru_buri_regular.ttf"
            "ddulgi_mayo" -> "fonts/ddulgi_mayo.otf"
            "paperlogy_bold" -> "fonts/paperlogy_bold.ttf"
            "nexon_lv1_gothic" -> "fonts/nexon_lv1_gothic.ttf"
            "poppins" -> "fonts/poppins_regular.ttf"
            else -> "fonts/pretendard_regular.otf"
        }
        return runCatching { Typeface.createFromAsset(context.assets, assetPath) }
            .getOrElse { Typeface.create(Typeface.SANS_SERIF, Typeface.NORMAL) }
    }
}
