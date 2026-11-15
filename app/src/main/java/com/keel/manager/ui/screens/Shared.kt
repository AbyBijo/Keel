package com.keel.manager.ui.screens

import androidx.compose.foundation.background
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.keel.manager.data.Person
import com.keel.manager.data.Task
import com.keel.manager.data.Team
import com.keel.manager.data.isDueSoon
import com.keel.manager.data.isOverdue
import com.keel.manager.data.startOfDayMillis
import com.keel.manager.ui.components.KeelCard
import com.keel.manager.ui.components.KeelCheckbox
import com.keel.manager.ui.components.PersonAvatar
import com.keel.manager.ui.components.keelClickable
import com.keel.manager.ui.theme.KeelColors
import com.keel.manager.ui.theme.KeelType
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

// ---------------------------------------------------------------------------
// Dates & labels
// ---------------------------------------------------------------------------

private val DATE_FMT = DateTimeFormatter.ofPattern("EEE, d MMM")

fun formatDueDate(dueMillis: Long?): String {
    if (dueMillis == null) return "No due date"
    val today = LocalDate.now()
    val date = Instant.ofEpochMilli(dueMillis).atZone(ZoneId.systemDefault()).toLocalDate()
    return when {
        date == today -> "Today"
        date == today.plusDays(1) -> "Tomorrow"
        date == today.minusDays(1) -> "Yesterday"
        else -> date.format(DATE_FMT)
    }
}

fun formatDateLong(millis: Long): String {
    val date = Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()).toLocalDate()
    return date.format(DateTimeFormatter.ofPattern("EEEE, d MMMM yyyy"))
}

/** (label, colour) for a task's due state. */
@Composable
fun dueLabel(task: Task): Pair<String, Color> {
    val overdue = KeelColors.LightOverdue
    val success = MaterialTheme.colorScheme.primary
    return when {
        task.isDone -> "Done" to MaterialTheme.colorScheme.onSurfaceVariant
        isOverdue(task) -> "Overdue · ${formatDueDate(task.dueDate)}" to overdue
        isDueSoon(task) -> "Due ${formatDueDate(task.dueDate)}" to success
        task.dueDate != null -> formatDueDate(task.dueDate) to MaterialTheme.colorScheme.onSurfaceVariant
        else -> "No due date" to MaterialTheme.colorScheme.onSurfaceVariant
    }
}

fun priorityLabel(priority: String): String = when (priority) {
    "high" -> "High"
    "medium" -> "Medium"
    "low" -> "Low"
    else -> "No priority"
}

fun teamColor(hex: String): Color = try {
    Color(android.graphics.Color.parseColor(hex))
} catch (_: IllegalArgumentException) {
    KeelColors.LightAccent
}

// ---------------------------------------------------------------------------
// Task tile — tap = overview sheet, chevron = full page.
// ---------------------------------------------------------------------------

@Composable
fun TaskTile(
    task: Task,
    team: Team?,
    assignees: List<Person>,
    onTap: () -> Unit,
    onChevron: () -> Unit,
    onToggleDone: () -> Unit,
    modifier: Modifier = Modifier,
    showTeam: Boolean = true,
) {
    val (label, labelColor) = dueLabel(task)
    KeelCard(modifier = modifier, onClick = onTap) {
        Row(verticalAlignment = Alignment.Top) {
            KeelCheckbox(checked = task.isDone, onCheckedChange = { onToggleDone() })
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    task.title,
                    style = KeelType.BodySemibold,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Spacer(Modifier.height(4.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (showTeam && team != null) {
                        Box(
                            Modifier
                                .size(8.dp)
                                .clip(androidx.compose.foundation.shape.CircleShape)
                                .background(teamColor(team.colorHex)),
                        )
                        Spacer(Modifier.width(6.dp))
                        Text(
                            team.name,
                            style = KeelType.Caption,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Spacer(Modifier.width(8.dp))
                    }
                    Text(label, style = KeelType.CaptionMedium, color = labelColor)
                }
                if (assignees.isNotEmpty()) {
                    Spacer(Modifier.height(8.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        for (p in assignees.take(3)) {
                            PersonAvatar(name = p.name, teamColor = null, size = 26.dp)
                        }
                        if (assignees.size > 3) {
                            Text(
                                "+${assignees.size - 3}",
                                style = KeelType.CaptionMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.align(Alignment.CenterVertically),
                            )
                        }
                    }
                }
            }
            Icon(
                Icons.Outlined.ChevronRight,
                contentDescription = "Open task",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .size(28.dp)
                    .then(keelClickable(onClick = onChevron))
                    .padding(2.dp),
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Person row — tap = overview sheet, chevron = full page.
// ---------------------------------------------------------------------------

@Composable
fun PersonRow(
    person: Person,
    teamColor: Color?,
    subtitle: String,
    onTap: () -> Unit,
    onChevron: () -> Unit,
    modifier: Modifier = Modifier,
) {
    KeelCard(modifier = modifier, onClick = onTap) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            PersonAvatar(name = person.name, teamColor = teamColor, size = 48.dp)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    person.name,
                    style = KeelType.BodySemibold,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Spacer(Modifier.height(2.dp))
                Text(
                    subtitle,
                    style = KeelType.Caption,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Icon(
                Icons.Outlined.ChevronRight,
                contentDescription = "Open person",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .size(28.dp)
                    .then(keelClickable(onClick = onChevron))
                    .padding(2.dp),
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Team card — tap = overview sheet, chevron = full team page.
// ---------------------------------------------------------------------------

@Composable
fun TeamCard(
    team: Team,
    memberCount: Int,
    progress: Double,
    doneCount: Int,
    totalCount: Int,
    onTap: () -> Unit,
    onChevron: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val color = teamColor(team.colorHex)
    KeelCard(modifier = modifier, onClick = onTap) {
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier
                        .size(12.dp)
                        .clip(androidx.compose.foundation.shape.CircleShape)
                        .background(color),
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    team.name,
                    style = KeelType.SectionTitle,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Icon(
                    Icons.Outlined.ChevronRight,
                    contentDescription = "Open team",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier
                        .size(28.dp)
                        .then(keelClickable(onClick = onChevron))
                        .padding(2.dp),
                )
            }
            Spacer(Modifier.height(8.dp))
            Text(
                "$memberCount member${if (memberCount == 1) "" else "s"} · $doneCount/$totalCount tasks done",
                style = KeelType.Caption,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(10.dp))
            // Progress bar
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(6.dp)
                    .clip(androidx.compose.foundation.shape.CircleShape)
                    .background(MaterialTheme.colorScheme.surfaceVariant),
            ) {
                Box(
                    Modifier
                        .fillMaxWidth(progress.toFloat().coerceIn(0f, 1f))
                        .height(6.dp)
                        .clip(androidx.compose.foundation.shape.CircleShape)
                        .background(color),
                )
            }
        }
    }
}

/** Section heading used across screens. */
@Composable
fun SectionHeader(title: String, actionLabel: String? = null, onAction: (() -> Unit)? = null) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = KeelType.SectionTitle, color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.weight(1f))
        if (actionLabel != null && onAction != null) {
            Text(
                actionLabel,
                style = KeelType.CaptionMedium,
                color = MaterialTheme.colorScheme.primary,
                modifier = keelClickable(onClick = onAction),
            )
        }
    }
}
