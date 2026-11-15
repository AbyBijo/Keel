package com.keel.manager.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.keel.manager.CreateKind
import com.keel.manager.KeelNav
import com.keel.manager.Tab
import com.keel.manager.data.HomeStats
import com.keel.manager.data.greetingFor
import com.keel.manager.ui.KeelViewModel
import com.keel.manager.ui.components.EmptyState
import com.keel.manager.ui.components.KeelCard
import com.keel.manager.ui.components.ProgressRing
import com.keel.manager.ui.components.keelClickable
import com.keel.manager.ui.theme.KeelColors
import com.keel.manager.ui.theme.KeelRadii
import com.keel.manager.ui.theme.KeelType
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

/**
 * Home: org + date header (tap = org switcher), greeting, dark progress
 * dial with count-up, 3 stat tiles, Up next, horizontal team cards.
 */
@Composable
fun HomeScreen(viewModel: KeelViewModel, nav: KeelNav) {
    val org by viewModel.activeOrg.collectAsState()
    val stats by viewModel.stats.collectAsState()
    val upNext by viewModel.upNext.collectAsState()
    val teams by viewModel.teams.collectAsState()
    val tasks by viewModel.tasks.collectAsState()
    val teamMembers by viewModel.teamMembers.collectAsState()
    val taskAssignees by viewModel.taskAssignees.collectAsState()
    val listState = rememberLazyListState()

    // Tap active tab scrolls to top.
    val signal = nav.scrollTopSignal
    LaunchedEffect(signal) {
        if (signal > 0) listState.animateScrollToItem(0)
    }

    val now = LocalDateTime.now()
    val greeting = greetingFor(now.hour)

    LazyColumn(
        state = listState,
        modifier = Modifier.fillMaxSize().padding(horizontal = 20.dp),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(top = 16.dp, bottom = 120.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // -- header: org + date, search -------------------------------------
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(
                    Modifier
                        .weight(1f)
                        .then(keelClickable(onClick = { nav.showOrgSwitcher = true })),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            org?.name ?: "Keel",
                            style = KeelType.Title,
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                        Icon(
                            Icons.Outlined.ChevronRight,
                            contentDescription = "Switch organization",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(20.dp),
                        )
                    }
                    Text(
                        now.format(DateTimeFormatter.ofPattern("EEEE, d MMMM")),
                        style = KeelType.Caption,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Box(
                    modifier = Modifier
                        .size(44.dp)
                        .clip(RoundedCornerShape(14.dp))
                        .background(MaterialTheme.colorScheme.surface)
                        .then(keelClickable(onClick = { nav.showSearch = true })),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Icons.Outlined.Search,
                        contentDescription = "Search",
                        tint = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.size(22.dp),
                    )
                }
            }
        }

        // -- greeting ---------------------------------------------------------
        item {
            Text(
                "$greeting.",
                style = KeelType.Display,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.padding(top = 4.dp),
            )
        }

        // -- progress dial ------------------------------------------------------
        item {
            DialCard(stats = stats, modifier = Modifier.fillMaxWidth())
        }

        // -- 3 stat tiles ---------------------------------------------------------
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
                val open = stats.total - stats.done
                StatTile("Open", "$open", Modifier.weight(1f))
                StatTile("Overdue", "${stats.overdue}", Modifier.weight(1f))
                StatTile("Due soon", "${stats.dueSoon}", Modifier.weight(1f))
            }
        }

        // -- up next ---------------------------------------------------------------
        item {
            SectionHeader("Up next", actionLabel = if (upNext.isNotEmpty()) "See all" else null) {
                nav.selectTab(Tab.TASKS)
            }
        }
        if (upNext.isEmpty()) {
            item {
                EmptyState(
                    title = "Nothing on deck",
                    body = "No open tasks right now. Add one and it will show up here.",
                    actionLabel = "Add a task",
                    onAction = { nav.createKind = CreateKind.TASK },
                )
            }
        } else {
            items(upNext, key = { it.id }) { task ->
                val team = teams.firstOrNull { t -> t.id == task.teamId }
                TaskTile(
                    task = task,
                    team = team,
                    assignees = taskAssignees[task.id] ?: emptyList(),
                    onTap = { nav.taskSheetId = task.id },
                    onChevron = { nav.taskPageId = task.id },
                    onToggleDone = { viewModel.toggleTaskDone(task) },
                )
            }
        }

        // -- teams -------------------------------------------------------------------
        item {
            SectionHeader("Teams", actionLabel = if (teams.isNotEmpty()) "See all" else null) {
                nav.selectTab(Tab.TEAMS)
            }
        }
        if (teams.isEmpty()) {
            item {
                EmptyState(
                    title = "No teams yet",
                    body = "Group people into teams to see progress at a glance.",
                    actionLabel = "Create a team",
                    onAction = { nav.createKind = CreateKind.TEAM },
                )
            }
        } else {
            item {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(teams, key = { it.id }) { team ->
                        val teamTasks = tasks.filter { t -> t.teamId == team.id }
                        val done = teamTasks.count { it.isDone }
                        TeamCard(
                            team = team,
                            memberCount = teamMembers[team.id]?.size ?: 0,
                            progress = if (teamTasks.isEmpty()) 0.0 else done.toDouble() / teamTasks.size,
                            doneCount = done,
                            totalCount = teamTasks.size,
                            onTap = { nav.teamSheetId = team.id },
                            onChevron = { nav.teamPageId = team.id },
                            modifier = Modifier.width(260.dp),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun DialCard(stats: HomeStats, modifier: Modifier = Modifier) {
    val total = stats.total
    val done = stats.done
    val progress = if (total == 0) 0f else done.toFloat() / total
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(KeelRadii.Card))
            .background(KeelColors.DialCard)
            .padding(20.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            ProgressRing(progress = progress, size = 132.dp, strokeWidth = 11.dp) { animated ->
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        "${(animated * 100).toInt()}%",
                        style = KeelType.Display.copy(fontSize = 28.sp),
                        color = Color.White,
                    )
                    Text("done", style = KeelType.Caption, color = Color.White.copy(alpha = 0.7f))
                }
            }
            Spacer(Modifier.width(20.dp))
            Column {
                Text(
                    if (total == 0) "Nothing yet" else "$done of $total tasks done",
                    style = KeelType.SectionTitle,
                    color = Color.White,
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    when {
                        total == 0 -> "Add your first task to get started."
                        stats.overdue > 0 -> "${stats.overdue} overdue — worth a look first."
                        stats.dueSoon > 0 -> "${stats.dueSoon} due soon."
                        else -> "Everything is on track."
                    },
                    style = KeelType.Body,
                    color = Color.White.copy(alpha = 0.75f),
                )
            }
        }
    }
}

@Composable
private fun StatTile(label: String, value: String, modifier: Modifier = Modifier) {
    KeelCard(modifier = modifier) {
        Column {
            Text(value, style = KeelType.Title, color = MaterialTheme.colorScheme.onSurface)
            Spacer(Modifier.height(2.dp))
            Text(label, style = KeelType.Caption, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
