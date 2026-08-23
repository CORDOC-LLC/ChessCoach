package com.chesscoach.android.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight

/**
 * Tier 3 design system -- NOT `MaterialTheme`. A direct Kotlin port of the
 * iOS "Living Themes" model (`Sources/GemmaChessCore/Theme/Theme.swift`):
 * 7 editable color tokens the app is built from, with everything else
 * (muted/faint text, card style, background gradient) DERIVED from those,
 * same as the Swift side. This app hardcodes the default "Gambit Room"
 * preset rather than porting the full theme-picker/editor -- Android has no
 * equivalent screen (yet); the token *shape* still matches so a future port
 * of the picker slots in without restructuring this object.
 *
 * Every screen reads colors from here, never from `MaterialTheme.colorScheme`
 * -- mixing the two token systems produces visual drift that's hard to spot
 * in review (see kd-android-convert skill, "Tier 3, not MaterialTheme").
 */
object ChessCoachTheme {
    // The 7 tokens, hex-for-hex from `Theme.gambit` in Theme.swift.
    val accent = Color(0xFF2F8360)
    val accent2 = Color(0xFFC9A24B)
    val bg = Color(0xFF140F0A)
    val surface = Color(0xFF281E14)
    val text = Color(0xFFF3EAD4)
    val boardLight = Color(0xFFE8D9B8)
    val boardDark = Color(0xFF6F4A2C)

    // Derived, matching Theme.swift's computed properties exactly.
    val onAccent = Color(0xFF15120C) // accent's luminance is well under 0.6 -> light text
    val mutedText = text.copy(alpha = 0.55f)
    val faintText = text.copy(alpha = 0.38f)
    val cardBackground = surface.copy(alpha = 0.84f)
    val cardBorder = accent2.copy(alpha = 0.22f)
    val glow = accent2.copy(alpha = 0.16f)

    /** `TypePersonality.elegant`'s displayFont: bold serif, matching the
     *  Gambit preset's `type` -- see `TypePersonality.displayFont(size:)`. */
    val displayFontFamily = FontFamily.Serif
    val displayFontWeight = FontWeight.Bold
    val displayLetterSpacingSp = 0.5f

    /** Standard corner radii used throughout the iOS source (`grep -c
     *  cornerRadius` in Sources/GemmaChessCore/UI): 16 is the dominant card
     *  radius, 14 for compact secondary cards/chips, 26 for the home emblem. */
    object Radius {
        const val card = 16
        const val chip = 14
        const val emblem = 26
        const val pill = 30
    }

    object Space {
        const val s2 = 2
        const val s4 = 4
        const val s6 = 6
        const val s8 = 8
        const val s10 = 10
        const val s12 = 12
        const val s14 = 14
        const val s16 = 16
        const val s28 = 28
        const val s32 = 32
    }
}

val LocalChessCoachTheme = staticCompositionLocalOf { ChessCoachTheme }

@Composable
fun ChessCoachAppTheme(content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalChessCoachTheme provides ChessCoachTheme, content = content)
}
