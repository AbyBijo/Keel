package com.keel.manager.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.keel.manager.CreateKind
import com.keel.manager.KeelNav
import com.keel.manager.ui.KeelViewModel
import com.keel.manager.ui.components.EmptyState
import com.keel.manager.ui.components.KeelButton
import com.keel.manager.ui.components.KeelCard
import com.keel.manager.ui.components.KeelChip
import com.keel.manager.ui.components.LabelValueRow
import com.keel.manager.ui.components.PersonAvatar
import com.keel.manager.ui.components.keelClickable
import com.keel.manager.ui.theme.KeelType
import kotlinx.coroutines.launch

/** Teams tab: cards. Tap = overview sheet, chevron = full team page. */
@Composable
fun TeamsScreen(viewModel: KeelViewModel, nav: KeelNav) {
    val teams by viewModel.teams.collectAsState()
    val tasks by viewModel.tasks.collectAsState()
    val teamMembers by viewModel.teamMembers.collectAsState()
    val listState = rememberLazyListState()

    val signal = nav.scrollTopSignal
    LaunchedEffect(signal) {
        if (signal > 0) listState.animateScrollToItem(0)
    }

    Column(Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 16.dp)) {
        Text("Teams", style = KeelType.Display, color = MaterialTheme.colorScheme.onSurface)
        Spacer(Modifier.height(12.dp))
        if (teams.isEmpty()) {
            EmptyState(
                title = "No teams yet",
                body = "Teams group people and their work. Create one to get started.",
                actionLabel = "Create a team",
                onAction = { nav.createKind = CreateKind.TEAM },
            )
        } else {
            LazyColumn(
                state = listState,
                verticalArrangement = Arrangement.spacedBy(12.dp),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 120.dp),
            ) {
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
                    )
                }
            }
        }
    }
}

/** Team overview sheet — quick buttons + leader + main task + members. */
@Composable
fun TeamOverviewSheet(viewModel: KeelViewModel, nav: KeelNav, teamId: String, onDismiss: () -> Unit) {
    val team by viewModel.repository.watchTeam(teamId).collectAsState(initial = null)
    val tasks by viewModel.tasks.collectAsState()
    val teamMembers by viewModel.teamMembers.collectAsState()
    val current = team ?: return
    val members = teamMembers[teamId] ?: emptyList()
    val leader = members.firstOrNull { it.id == current.leaderPersonId }
    val teamTasks = tasks.filter { t -> t.teamId == teamId }
    val done = teamTasks.count { it.isDone }
    val mainTask = teamTasks.firstOrNull { it.id == current.mainTaskId }

    KeelSheet(onDismiss = onDismiss) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            androidx.compose.foundation.layout.Box(
                modifier = Modifier
                    .size(12.dp)
                    .clip(androidx.compose.foundation.shape.CircleShape)
                    .background(teamColor(current.colorHex)),
            )
            Spacer(Modifier.width(8.dp))
            Text(current.name, style = KeelType.Title, color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.weight(1f))
        }
        Spacer(Modifier.height(4.dp))
        Text(
            "${members.size} member${if (members.size == 1) "" else "s"} · $done/${teamTasks.size} tasks done",
            style = KeelType.Caption,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(16.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            KeelButton(
                label = "Open team",
                onClick = { onDismiss(); nav.teamPageId = current.id },
                modifier = Modifier.weight(1f),
            )
            KeelButton(
                label = "Edit",
                onClick = { onDismiss(); nav.teamPageId = current.id },
                leadingIcon = Icons.Outlined.Edit,
                primary = false,
                modifier = Modifier.weight(1f),
            )
            KeelButton(
                label = "Delete",
                onClick = {
                    viewModel.deleteTeam(current)
                    onDismiss()
                },
                leadingIcon = Icons.Outlined.Delete,
                primary = false,
                modifier = Modifier.weight(1f),
            )
        }
        Spacer(Modifier.height(16.dp))
        LabelValueRow("Leader", leader?.name ?: "—")
        Spacer(Modifier.height(8.dp))
        LabelValueRow("Main task", mainTask?.title ?: "None set")
        if (mainTask != null) {
            Spacer(Modifier.height(8.dp))
            KeelButton(
                label = if (mainTask.isDone) "Main task done ✓" else "Complete main task",
                onClick = {
                    if (!mainTask.isDone) viewModel.toggleTaskDone(mainTask)
                    onDismiss()
                },
                primary = false,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        if (members.isNotEmpty()) {
            Spacer(Modifier.height(16.dp))
            Text("Members", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
            for (m in members) {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(vertical = 4.dp)) {
                    PersonAvatar(name = m.name, teamColor = teamColor(current.colorHex), size = 36.dp)
                    Spacer(Modifier.width(12.dp))
                    Text(m.name, style = KeelType.Body, color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.weight(1f))
                    if (m.id == current.leaderPersonId) {
                        Text("Leader", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.primary)
                    }
                }
            }
        }
    }
}

/** Full team page: progress, main task, members, tasks, edit. */
@Composable
fun TeamPage(viewModel: KeelViewModel, nav: KeelNav, teamId: String) {
    val team by viewModel.repository.watchTeam(teamId).collectAsState(initial = null)
    val tasks by viewModel.tasks.collectAsState()
    val people by viewModel.people.collectAsState()
    val teamMembers by viewModel.teamMembers.collectAsState()
    val scope = rememberCoroutineScope()
    val current = team ?: run {
        LaunchedEffect(Unit) { nav.teamPageId = null }
        return
    }
    val members = teamMembers[teamId] ?: emptyList()
    val teamTasks = tasks.filter { t -> t.teamId == teamId }
    val done = teamTasks.count { it.isDone }
    val progress = if (teamTasks.isEmpty()) 0.0 else done.toDouble() / teamTasks.size
    val mainTask = teamTasks.firstOrNull { it.id == current.mainTaskId }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    var leaderPick by remember { mutableStateOf<String?>(null) }

    Column(Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            androidx.compose.foundation.layout.Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(androidx.compose.foundation.shape.CircleShape)
                    .background(MaterialTheme.colorScheme.surface)
                    .then(keelClickable(onClick = { nav.teamPageId = null })),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back", tint = MaterialTheme.colorScheme.onSurface)
            }
            Spacer(Modifier.width(12.dp))
            Text(current.name, style = KeelType.Title, color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.weight(1f))
            Text(
                "Delete",
                style = KeelType.CaptionMedium,
                color = MaterialTheme.colorScheme.error,
                modifier = keelClickable(onClick = { showDeleteConfirm = true }),
            )
        }
        Spacer(Modifier.height(16.dp))
        androidx.compose.foundation.lazy.LazyColumn(
            verticalArrangement = Arrangement.spacedBy(12.dp),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 120.dp),
        ) {
            item {
                KeelCard {
                    Column {
                        Text(
                            "$done of ${teamTasks.size} tasks done",
                            style = KeelType.SectionTitle,
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                        Spacer(Modifier.height(10.dp))
                        androidx.compose.foundation.layout.Box(
                            Modifier
                                .fillMaxWidth()
                                .height(8.dp)
                                .clip(androidx.compose.foundation.shape.CircleShape)
                                .background(MaterialTheme.colorScheme.surfaceVariant),
                        ) {
                            androidx.compose.foundation.layout.Box(
                                Modifier
                                    .fillMaxWidth(progress.toFloat().coerceIn(0f, 1f))
                                    .height(8.dp)
                                    .clip(androidx.compose.foundation.shape.CircleShape)
                                    .background(teamColor(current.colorHex)),
                            )
                        }
                        Spacer(Modifier.height(12.dp))
                        LabelValueRow("Leader", members.firstOrNull { it.id == current.leaderPersonId }?.name ?: "—")
                        Spacer(Modifier.height(8.dp))
                        LabelValueRow("Main task", mainTask?.title ?: "None set")
                    }
                }
            }
            if (mainTask != null) {
                item { SectionHeader("Main task") }
                item {
                    TaskTile(
                        task = mainTask,
                        team = current,
                        assignees = emptyList(),
                        onTap = { nav.taskSheetId = mainTask.id },
                        onChevron = { nav.taskPageId = mainTask.id },
                        onToggleDone = { viewModel.toggleTaskDone(mainTask) },
                    )
                }
                item {
                    Text(
                        "Change main task:",
                        style = KeelType.CaptionMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        KeelChip(label = "None", selected = current.mainTaskId == null, onClick = {
                            scope.launch { viewModel.repository.setMainTask(current.id, null) }
                        })
                        for (t in teamTasks.filter { !it.isDone && it.id != current.mainTaskId }) {
                            KeelChip(label = t.title, selected = false, onClick = {
                                scope.launch { viewModel.repository.setMainTask(current.id, t.id) }
                            })
                        }
                    }
                }
            }
            item { SectionHeader("Members (${members.size})") }
            items(members, key = { it.id }) { m ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    PersonAvatar(name = m.name, teamColor = teamColor(current.colorHex), size = 40.dp)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(m.name, style = KeelType.BodySemibold, color = MaterialTheme.colorScheme.onSurface)
                        Text(
                            if (m.id == current.leaderPersonId) "Leader · ${m.roleTitle}" else m.roleTitle,
                            style = KeelType.Caption,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    if (m.id == current.leaderPersonId) {
                        Text("Leader", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.primary)
                    } else {
                        Text(
                            "Remove",
                            style = KeelType.CaptionMedium,
                            color = MaterialTheme.colorScheme.error,
                            modifier = keelClickable(onClick = {
                                scope.launch { viewModel.repository.removeTeamMember(current.id, m.id) }
                            }),
                        )
                    }
                }
            }
            // Change leader: pick a member; the old leader stays a member.
            // (Rule 4 — exactly one leader, who must be a member.)
            if (leaderPick != null) {
                item {
                    KeelCard {
                        Column {
                            Text("Pick the new leader", style = KeelType.BodySemibold, color = MaterialTheme.colorScheme.onSurface)
                            Spacer(Modifier.height(8.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                for (m in members.filter { it.id != current.leaderPersonId }) {
                                    KeelChip(label = m.name, selected = false, onClick = {
                                        scope.launch {
                                            viewModel.repository.updateTeam(current.id, leaderPersonId = m.id)
                                            leaderPick = null
                                        }
                                    })
                                }
                            }
                            Spacer(Modifier.height(8.dp))
                            Text("Cancel", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.primary,
                                modifier = keelClickable(onClick = { leaderPick = null }))
                        }
                    }
                }
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (p in people.filter { person -> members.none { it.id == person.id } }) {
                        KeelChip(label = "+ ${p.name}", selected = false, onClick = {
                            scope.launch { viewModel.repository.addTeamMember(current.id, p.id) }
                        })
                    }
                }
            }
            item {
                KeelButton(
                    label = "Change leader",
                    onClick = { leaderPick = "pick" },
                    primary = false,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            item { SectionHeader("Tasks (${teamTasks.size})") }
            if (teamTasks.isEmpty()) {
                item {
                    EmptyState(
                        title = "No tasks in this team",
                        body = "Add a task and assign it to this team.",
                        actionLabel = "Add a task",
                        onAction = { nav.createKind = CreateKind.TASK },
                    )
                }
            } else {
                items(teamTasks, key = { it.id }) { t ->
                    TaskTile(
                        task = t,
                        team = current,
                        assignees = emptyList(),
                        onTap = { nav.taskSheetId = t.id },
                        onChevron = { nav.taskPageId = t.id },
                        onToggleDone = { viewModel.toggleTaskDone(t) },
                        showTeam = false,
                    )
                }
            }
        }
    }
    if (showDeleteConfirm) {
        ConfirmDialog(
            title = "Delete this team?",
            body = "Its people and tasks are kept — they just lose the team.",
            confirmLabel = "Delete",
            onConfirm = {
                showDeleteConfirm = false
                nav.teamPageId = null
                viewModel.deleteTeam(current)
            },
            onDismiss = { showDeleteConfirm = false },
        )
    }
}
