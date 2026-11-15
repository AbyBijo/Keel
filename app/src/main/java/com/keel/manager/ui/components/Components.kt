package com.keel.manager.ui.components

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.keel.manager.data.initialsOf
import com.keel.manager.ui.theme.KeelColors
import com.keel.manager.ui.theme.KeelMotion
import com.keel.manager.ui.theme.KeelRadii
import com.keel.manager.ui.theme.KeelType
import com.keel.manager.ui.theme.LocalReduceMotion
import com.keel.manager.ui.theme.tint16

// ---------------------------------------------------------------------------
// Press feedback — neutral grey indication, NEVER blue.
// (Universal rule: no blue tap highlight, no blue focus ring.)
// ---------------------------------------------------------------------------

/** A clickable with a neutral-grey press indication and haptics. */
@Composable
fun keelClickable(
    onClick: () -> Unit,
    haptic: Boolean = false,
): Modifier {
    val haptics = LocalHapticFeedback.current
    return Modifier.clickable(
        interactionSource = remember { MutableInteractionSource() },
        // No ripple colour at all: indication comes from the component's own
        // pressed state (a grey tint) where it matters; plain rows use none.
        indication = null,
        role = Role.Button,
    ) {
        if (haptic) haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        onClick()
    }
}

// ---------------------------------------------------------------------------
// Cards, chips, buttons
// ---------------------------------------------------------------------------

@Composable
fun KeelCard(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    val base = modifier
        .fillMaxWidth()
        .clip(RoundedCornerShape(KeelRadii.Card))
        .background(MaterialTheme.colorScheme.surface)
        .border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(KeelRadii.Card))
    val withClick = if (onClick != null) base.then(keelClickable(onClick = onClick)) else base
    Box(modifier = withClick.padding(16.dp)) { content() }
}

@Composable
fun KeelChip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    leadingIcon: ImageVector? = null,
) {
    val accent = MaterialTheme.colorScheme.primary
    val bg = if (selected) accent.copy(alpha = 0.14f) else MaterialTheme.colorScheme.surface
    val fg = if (selected) accent else MaterialTheme.colorScheme.onSurfaceVariant
    Box(
        modifier = modifier
            .clip(CircleShape)
            .background(bg)
            .border(1.dp, if (selected) accent else MaterialTheme.colorScheme.outline, CircleShape)
            .then(keelClickable(onClick = onClick))
            .padding(horizontal = 14.dp, vertical = 9.dp),
        contentAlignment = Alignment.Center,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (leadingIcon != null) {
                Icon(leadingIcon, contentDescription = null, tint = fg, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(6.dp))
            }
            Text(label, style = KeelType.CaptionMedium, color = fg)
        }
    }
}

@Composable
fun KeelButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    primary: Boolean = true,
    leadingIcon: ImageVector? = null,
) {
    val accent = MaterialTheme.colorScheme.primary
    val bg = when {
        !enabled -> MaterialTheme.colorScheme.outline
        primary -> accent
        else -> MaterialTheme.colorScheme.surface
    }
    val fg = when {
        !enabled -> MaterialTheme.colorScheme.onSurfaceVariant
        primary -> Color.White
        else -> MaterialTheme.colorScheme.onSurface
    }
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(KeelRadii.Button))
            .background(bg)
            .border(
                1.dp,
                if (primary || !enabled) Color.Transparent else MaterialTheme.colorScheme.outline,
                RoundedCornerShape(KeelRadii.Button),
            )
            .then(if (enabled) keelClickable(onClick = onClick, haptic = true) else Modifier)
            .padding(horizontal = 20.dp, vertical = 13.dp),
        contentAlignment = Alignment.Center,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (leadingIcon != null) {
                Icon(leadingIcon, contentDescription = null, tint = fg, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
            }
            Text(label, style = KeelType.BodySemibold, color = fg)
        }
    }
}

// ---------------------------------------------------------------------------
// Avatar — 2.5px ring in first-team colour, 16% tint, initials in that colour.
// No team = neutral grey (kit rule).
// ---------------------------------------------------------------------------

@Composable
fun PersonAvatar(
    name: String,
    teamColor: Color?,
    size: Dp = 48.dp,
    modifier: Modifier = Modifier,
) {
    val ring = teamColor ?: KeelColors.LightNoTeam
    val tint = teamColor?.tint16() ?: MaterialTheme.colorScheme.surfaceVariant
    val fg = teamColor ?: MaterialTheme.colorScheme.onSurfaceVariant
    Box(
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .background(tint)
            .border(2.5.dp, ring, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            initialsOf(name),
            style = KeelType.BodySemibold.copy(
                fontSize = (size.value * 0.36f).coerceAtLeast(11f).sp,
            ),
            color = fg,
        )
    }
}

// ---------------------------------------------------------------------------
// Squircle checkbox, 9dp radius, teal when checked.
// ---------------------------------------------------------------------------

@Composable
fun KeelCheckbox(
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    size: Dp = 26.dp,
) {
    val accent = MaterialTheme.colorScheme.primary
    val haptics = LocalHapticFeedback.current
    Box(
        modifier = modifier
            .size(size)
            .clip(RoundedCornerShape(KeelRadii.Checkbox))
            .background(if (checked) accent else Color.Transparent)
            .border(
                1.5.dp,
                if (checked) accent else MaterialTheme.colorScheme.outline,
                RoundedCornerShape(KeelRadii.Checkbox),
            )
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                role = Role.Checkbox,
            ) {
                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                onCheckedChange(!checked)
            },
        contentAlignment = Alignment.Center,
    ) {
        if (checked) {
            Icon(Icons.Outlined.Check, contentDescription = null, tint = Color.White, modifier = Modifier.size(size * 0.7f))
        }
    }
}

// ---------------------------------------------------------------------------
// Progress ring with count-up (Home dial). Reduce-motion: jumps to value.
// ---------------------------------------------------------------------------

@Composable
fun ProgressRing(
    progress: Float,
    size: Dp = 148.dp,
    strokeWidth: Dp = 12.dp,
    modifier: Modifier = Modifier,
    content: @Composable (animatedProgress: Float) -> Unit = {},
) {
    val reduceMotion = LocalReduceMotion.current
    val animated = remember { Animatable(0f) }
    LaunchedEffect(progress) {
        if (reduceMotion) {
            animated.snapTo(progress)
        } else {
            animated.animateTo(progress, animationSpec = tween(KeelMotion.DialMs))
        }
    }
    val value = animated.value
    Box(modifier = modifier.size(size), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(size)) {
            val stroke = strokeWidth.toPx()
            val radius = (size.toPx() - stroke) / 2f
            val center = Offset(size.toPx() / 2f, size.toPx() / 2f)
            // Track
            drawArc(
                color = Color.White.copy(alpha = 0.14f),
                startAngle = -90f,
                sweepAngle = 360f,
                useCenter = false,
                topLeft = Offset(center.x - radius, center.y - radius),
                size = androidx.compose.ui.geometry.Size(radius * 2, radius * 2),
                style = Stroke(width = stroke, cap = StrokeCap.Round),
            )
            // Value — teal accent on the dark dial card
            drawArc(
                color = Color(0xFF3CC3CF),
                startAngle = -90f,
                sweepAngle = 360f * value,
                useCenter = false,
                topLeft = Offset(center.x - radius, center.y - radius),
                size = androidx.compose.ui.geometry.Size(radius * 2, radius * 2),
                style = Stroke(width = stroke, cap = StrokeCap.Round),
            )
        }
        content(value)
    }
}

// ---------------------------------------------------------------------------
// Segmented control (Settings appearance / filters).
// ---------------------------------------------------------------------------

@Composable
fun SegmentedControl(
    options: List<String>,
    selectedIndex: Int,
    onSelected: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        options.forEachIndexed { i, label ->
            val selected = i == selectedIndex
            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(9.dp))
                    .background(if (selected) MaterialTheme.colorScheme.surface else Color.Transparent)
                    .then(keelClickable(onClick = { onSelected(i) }))
                    .padding(vertical = 8.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    label,
                    style = KeelType.CaptionMedium,
                    color = if (selected) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Text field — neutral grey border on focus, never blue.
// ---------------------------------------------------------------------------

@Composable
fun KeelTextField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String = "",
    singleLine: Boolean = true,
    keyboardType: KeyboardType = KeyboardType.Text,
    leadingIcon: @Composable (() -> Unit)? = null,
    trailingIcon: @Composable (() -> Unit)? = null,
) {
    val border = MaterialTheme.colorScheme.outline
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(14.dp))
            .background(MaterialTheme.colorScheme.surface)
            .border(1.dp, border, RoundedCornerShape(14.dp))
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (leadingIcon != null) {
            leadingIcon()
            Spacer(Modifier.width(8.dp))
        }
        Box(Modifier.weight(1f)) {
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                singleLine = singleLine,
                textStyle = KeelType.Body.copy(color = MaterialTheme.colorScheme.onSurface),
                keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
                modifier = Modifier.fillMaxWidth(),
                decorationBox = { inner ->
                    if (value.isEmpty()) {
                        Text(placeholder, style = KeelType.Body, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    inner()
                },
            )
        }
        if (trailingIcon != null) {
            Spacer(Modifier.width(8.dp))
            trailingIcon()
        }
    }
}

// ---------------------------------------------------------------------------
// Empty state with one-tap action (every list has one).
// ---------------------------------------------------------------------------

@Composable
fun EmptyState(
    title: String,
    body: String,
    actionLabel: String,
    onAction: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 32.dp, horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(title, style = KeelType.SectionTitle, color = MaterialTheme.colorScheme.onSurface, textAlign = TextAlign.Center)
        Spacer(Modifier.height(6.dp))
        Text(body, style = KeelType.Body, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        Spacer(Modifier.height(16.dp))
        KeelButton(label = actionLabel, onClick = onAction)
    }
}

/** One-line label/value row, used in sheets and detail pages. */
@Composable
fun LabelValueRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, style = KeelType.Caption, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(
            value,
            style = KeelType.BodyMedium,
            color = MaterialTheme.colorScheme.onSurface,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}
