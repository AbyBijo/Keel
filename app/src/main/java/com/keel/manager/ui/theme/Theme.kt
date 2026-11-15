package com.keel.manager.ui.theme

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.keel.manager.R
import com.keel.manager.data.ThemeMode

// ---------------------------------------------------------------------------
// Kit tokens — tokens/design-tokens.json, copied exactly.
// ---------------------------------------------------------------------------

object KeelColors {
    // Light
    val LightBackground = Color(0xFFE9EEF1)
    val LightCard = Color(0xFFFFFFFF)
    val LightInk = Color(0xFF0D1B26)
    val LightMuted = Color(0xFF7B8894)
    val LightLine = Color(0xFFDCE3E8)
    val LightAccent = Color(0xFF0E7C86)
    val LightSuccess = Color(0xFF2E9C78)
    val LightOverdue = Color(0xFFE5604D)
    val LightNoTeam = Color(0xFF98A4AE)

    // Dark
    val DarkBackground = Color(0xFF0A1118)
    val DarkCard = Color(0xFF142029)
    val DarkInk = Color(0xFFEAF1F5)
    val DarkMuted = Color(0xFF8696A3)
    val DarkLine = Color(0xFF22313C)
    val DarkAccent = Color(0xFF3CC3CF)
    val DarkDialCard = Color(0xFF1B3340)

    // Shared
    val TealGradientTop = Color(0xFF12A0AB)
    val TealGradientBottom = Color(0xFF0B4F66)
    val DialCard = Color(0xFF1B3340)

    /** Team presets (kit), plus a custom picker in the UI. */
    val TeamPresets = listOf(
        Color(0xFFE5604D),
        Color(0xFF4F6BED),
        Color(0xFFE3A21A),
        Color(0xFF2E9C78),
        Color(0xFF9B5DE5),
        Color(0xFFD6478B),
    )
}

val Nunito = FontFamily(
    Font(R.font.nunito_bold, FontWeight.Bold),
    Font(R.font.nunito_extrabold, FontWeight.ExtraBold),
)
val Inter = FontFamily(
    Font(R.font.inter_regular, FontWeight.Normal),
    Font(R.font.inter_medium, FontWeight.Medium),
    Font(R.font.inter_semibold, FontWeight.SemiBold),
    Font(R.font.inter_bold, FontWeight.Bold),
)

object KeelType {
    /** Display: Nunito 800, 32/1.05, -0.8 tracking. */
    val Display = TextStyle(
        fontFamily = Nunito,
        fontWeight = FontWeight.ExtraBold,
        fontSize = 32.sp,
        lineHeight = 33.6.sp,
        letterSpacing = (-0.8).sp,
    )
    val Title = TextStyle(
        fontFamily = Nunito,
        fontWeight = FontWeight.ExtraBold,
        fontSize = 22.sp,
        lineHeight = 26.sp,
        letterSpacing = (-0.4).sp,
    )
    val SectionTitle = TextStyle(
        fontFamily = Nunito,
        fontWeight = FontWeight.ExtraBold,
        fontSize = 17.sp,
        lineHeight = 22.sp,
    )
    /** Body: Inter 15/1.35. */
    val Body = TextStyle(
        fontFamily = Inter,
        fontWeight = FontWeight.Normal,
        fontSize = 15.sp,
        lineHeight = 20.25.sp,
    )
    val BodyMedium = TextStyle(
        fontFamily = Inter,
        fontWeight = FontWeight.Medium,
        fontSize = 15.sp,
        lineHeight = 20.25.sp,
    )
    val BodySemibold = TextStyle(
        fontFamily = Inter,
        fontWeight = FontWeight.SemiBold,
        fontSize = 15.sp,
        lineHeight = 20.25.sp,
    )
    val Caption = TextStyle(
        fontFamily = Inter,
        fontWeight = FontWeight.Normal,
        fontSize = 13.sp,
        lineHeight = 17.5.sp,
    )
    val CaptionMedium = TextStyle(
        fontFamily = Inter,
        fontWeight = FontWeight.Medium,
        fontSize = 13.sp,
        lineHeight = 17.5.sp,
    )
    val Small = TextStyle(
        fontFamily = Inter,
        fontWeight = FontWeight.Medium,
        fontSize = 12.sp,
        lineHeight = 16.sp,
    )
}

object KeelRadii {
    val Card = 22.dp
    val SheetTop = 32.dp
    val Button = 18.dp
    val Checkbox = 9.dp
    val IconTile = 28.dp
}

/** Motion tokens — apple-design skill: critically-damped springs,
 * fades 180–260 ms, transform/opacity only. */
object KeelMotion {
    /** The default spring: stiffness ~300, damping ~26 (damping ratio 1.0). */
    fun <T> spring() = androidx.compose.animation.core.spring<T>(
        dampingRatio = Spring.DampingRatioNoBouncy,
        stiffness = 300f,
    )

    /** Gentle spring for large elements (sheets, dial). */
    fun <T> softSpring() = androidx.compose.animation.core.spring<T>(
        dampingRatio = Spring.DampingRatioNoBouncy,
        stiffness = 260f,
    )

    /** Fade duration in ms (180–260). */
    const val FadeMs = 220
    /** Sheet slide duration in ms. */
    const val SheetMs = 320
    /** Dial count-up duration in ms. */
    const val DialMs = 900
    /** Stagger between the three FAB pills in ms. */
    const val FabStaggerMs = 40
}

/** Reduce-motion flag, from Settings. When true, animations become
 * simple fades — no springs, no slides, no count-up. */
val LocalReduceMotion = compositionLocalOf { false }

private fun lightScheme(): ColorScheme = lightColorScheme(
    primary = KeelColors.LightAccent,
    onPrimary = Color.White,
    background = KeelColors.LightBackground,
    onBackground = KeelColors.LightInk,
    surface = KeelColors.LightCard,
    onSurface = KeelColors.LightInk,
    surfaceVariant = KeelColors.LightBackground,
    onSurfaceVariant = KeelColors.LightMuted,
    outline = KeelColors.LightLine,
    error = KeelColors.LightOverdue,
    onError = Color.White,
)

private fun darkScheme(): ColorScheme = darkColorScheme(
    primary = KeelColors.DarkAccent,
    onPrimary = Color(0xFF062A30),
    background = KeelColors.DarkBackground,
    onBackground = KeelColors.DarkInk,
    surface = KeelColors.DarkCard,
    onSurface = KeelColors.DarkInk,
    surfaceVariant = KeelColors.DarkBackground,
    onSurfaceVariant = KeelColors.DarkMuted,
    outline = KeelColors.DarkLine,
    error = KeelColors.LightOverdue,
    onError = Color.White,
)

/**
 * Keel theme. [mode] comes from Settings; SYSTEM follows the device.
 * [reduceMotion] switches every animation to a simple fade.
 */
@Composable
fun KeelTheme(
    mode: ThemeMode = ThemeMode.SYSTEM,
    reduceMotion: Boolean = false,
    content: @Composable () -> Unit,
) {
    val systemDark = isSystemInDarkTheme()
    val dark = when (mode) {
        ThemeMode.SYSTEM -> systemDark
        ThemeMode.LIGHT -> false
        ThemeMode.DARK -> true
    }
    val scheme = if (dark) darkScheme() else lightScheme()
    CompositionLocalProvider(LocalReduceMotion provides reduceMotion) {
        androidx.compose.material3.MaterialTheme(
            colorScheme = scheme,
            content = content,
        )
    }
}

/** The current accent, honouring the user's custom accent (Settings). */
@Composable
fun keelAccent(customHex: String?): Color {
    if (customHex.isNullOrBlank()) {
        return androidx.compose.material3.MaterialTheme.colorScheme.primary
    }
    return try {
        Color(android.graphics.Color.parseColor(customHex))
    } catch (_: IllegalArgumentException) {
        androidx.compose.material3.MaterialTheme.colorScheme.primary
    }
}

/** A colour at 16% opacity, for avatar tints (kit rule). */
fun Color.tint16(): Color = copy(alpha = 0.16f)
