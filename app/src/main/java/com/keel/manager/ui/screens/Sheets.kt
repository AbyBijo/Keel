package com.keel.manager.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.keel.manager.CreateKind
import com.keel.manager.KeelNav
import com.keel.manager.ui.KeelViewModel
import com.keel.manager.ui.components.KeelButton
import com.keel.manager.ui.components.KeelChip
import com.keel.manager.ui.components.KeelTextField
import com.keel.manager.ui.components.keelClickable
import com.keel.manager.ui.theme.KeelColors
import com.keel.manager.ui.theme.KeelRadii
import com.keel.manager.ui.theme.KeelType
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.launch

// ---------------------------------------------------------------------------
// Bottom sheet — 32dp top radius, drag handle, dimmed scrim.
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun KeelSheet(onDismiss: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(topStart = KeelRadii.SheetTop, topEnd = KeelRadii.SheetTop),
        dragHandle = {
            Box(
                Modifier
                    .padding(top = 12.dp)
                    .size(width = 36.dp, height = 5.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.outline),
            )
        },
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp),
        ) {
            content()
        }
    }
}

// ---------------------------------------------------------------------------
// Confirm dialog — neutral styling, no blue.
// ---------------------------------------------------------------------------

@Composable
fun ConfirmDialog(
    title: String,
    body: String,
    confirmLabel: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
    dismissLabel: String = "Cancel",
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title, style = KeelType.Title, color = MaterialTheme.colorScheme.onSurface) },
        text = { Text(body, style = KeelType.Body, color = MaterialTheme.colorScheme.onSurfaceVariant) },
        confirmButton = {
            Text(
                confirmLabel,
                style = KeelType.BodySemibold,
                color = MaterialTheme.colorScheme.error,
                modifier = keelClickable(onClick = onConfirm),
            )
        },
        dismissButton = {
            Text(
                dismissLabel,
                style = KeelType.BodySemibold,
                color = MaterialTheme.colorScheme.primary,
                modifier = keelClickable(onClick = onDismiss),
            )
        },
        containerColor = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(KeelRadii.Card),
    )
}

// ---------------------------------------------------------------------------
// Create sheet — Task / Person / Team.
// ---------------------------------------------------------------------------

@Composable
fun CreateSheet(viewModel: KeelViewModel, nav: KeelNav, kind: CreateKind, onDismiss: () -> Unit) {
    val org by viewModel.activeOrg.collectAsState()
    val teams by viewModel.teams.collectAsState()
    val people by viewModel.people.collectAsState()
    val scope = rememberCoroutineScope()
    val orgId = org?.id ?: return

    when (kind) {
        CreateKind.TASK -> CreateTaskForm(viewModel, orgId, teams, people, onDismiss)
        CreateKind.PERSON -> CreatePersonForm(viewModel, orgId, teams, onDismiss)
        CreateKind.TEAM -> CreateTeamForm(viewModel, orgId, people, onDismiss)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CreateTaskForm(
    viewModel: KeelViewModel,
    orgId: String,
    teams: List<com.keel.manager.data.Team>,
    people: List<com.keel.manager.data.Person>,
    onDismiss: () -> Unit,
) {
    var title by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf("") }
    var priority by remember { mutableStateOf("none") }
    var teamId by remember { mutableStateOf<String?>(null) }
    val assignees = remember { mutableStateListOf<String>() }
    var dueChoice by remember { mutableStateOf(0) } // 0 none, 1 today, 2 tomorrow, 3 in 3 days, 4 in a week
    val scope = rememberCoroutineScope()

    KeelSheet(onDismiss = onDismiss) {
        Text("New task", style = KeelType.Title, color = MaterialTheme.colorScheme.onSurface)
        Spacer(Modifier.height(16.dp))
        KeelTextField(value = title, onValueChange = { title = it }, placeholder = "Task title")
        Spacer(Modifier.height(12.dp))
        KeelTextField(value = notes, onValueChange = { notes = it }, placeholder = "Notes (optional)", singleLine = false)
        Spacer(Modifier.height(16.dp))
        Text("Due", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for ((i, label) in listOf("No date", "Today", "Tomorrow", "In 3 days", "In a week").withIndex()) {
                KeelChip(label = label, selected = dueChoice == i, onClick = { dueChoice = i })
            }
        }
        Spacer(Modifier.height(16.dp))
        Text("Priority", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (p in listOf("none", "low", "medium", "high")) {
                KeelChip(label = priorityLabel(p), selected = priority == p, onClick = { priority = p })
            }
        }
        if (teams.isNotEmpty()) {
            Spacer(Modifier.height(16.dp))
            Text("Team", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                KeelChip(label = "No team", selected = teamId == null, onClick = { teamId = null })
                for (t in teams) {
                    KeelChip(label = t.name, selected = teamId == t.id, onClick = { teamId = t.id })
                }
            }
        }
        if (people.isNotEmpty()) {
            Spacer(Modifier.height(16.dp))
            Text("Assign to", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
            androidx.compose.foundation.layout.FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                for (p in people) {
                    KeelChip(
                        label = p.name,
                        selected = assignees.contains(p.id),
                        onClick = {
                            if (assignees.contains(p.id)) assignees.remove(p.id) else assignees.add(p.id)
                        },
                    )
                }
            }
        }
        Spacer(Modifier.height(20.dp))
        KeelButton(
            label = "Create task",
            onClick = {
                if (title.isBlank()) return@KeelButton
                val due = when (dueChoice) {
                    1 -> LocalDate.now().atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
                    2 -> LocalDate.now().plusDays(1).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
                    3 -> LocalDate.now().plusDays(3).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
                    4 -> LocalDate.now().plusDays(7).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
                    else -> null
                }
                scope.launch {
                    viewModel.repository.createTask(
                        orgId = orgId,
                        title = title,
                        notes = notes,
                        dueDate = due,
                        priority = priority,
                        teamId = teamId,
                        assigneeIds = assignees.toList(),
                    )
                    onDismiss()
                }
            },
            enabled = title.isNotBlank(),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CreatePersonForm(
    viewModel: KeelViewModel,
    orgId: String,
    teams: List<com.keel.manager.data.Team>,
    onDismiss: () -> Unit,
) {
    var name by remember { mutableStateOf("") }
    var role by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf("") }
    var phone by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    val teamIds = remember { mutableStateListOf<String>() }
    val scope = rememberCoroutineScope()

    KeelSheet(onDismiss = onDismiss) {
        Text("New person", style = KeelType.Title, color = MaterialTheme.colorScheme.onSurface)
        Spacer(Modifier.height(16.dp))
        KeelTextField(value = name, onValueChange = { name = it }, placeholder = "Full name")
        Spacer(Modifier.height(12.dp))
        KeelTextField(value = role, onValueChange = { role = it }, placeholder = "Role (e.g. Designer)")
        Spacer(Modifier.height(12.dp))
        KeelTextField(value = phone, onValueChange = { phone = it }, placeholder = "Phone (optional)", keyboardType = androidx.compose.ui.text.input.KeyboardType.Phone)
        Spacer(Modifier.height(12.dp))
        KeelTextField(value = email, onValueChange = { email = it }, placeholder = "Email (optional)", keyboardType = androidx.compose.ui.text.input.KeyboardType.Email)
        Spacer(Modifier.height(12.dp))
        KeelTextField(value = notes, onValueChange = { notes = it }, placeholder = "Notes (optional)", singleLine = false)
        if (teams.isNotEmpty()) {
            Spacer(Modifier.height(16.dp))
            Text("Teams", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
            androidx.compose.foundation.layout.FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                for (t in teams) {
                    KeelChip(
                        label = t.name,
                        selected = teamIds.contains(t.id),
                        onClick = {
                            if (teamIds.contains(t.id)) teamIds.remove(t.id) else teamIds.add(t.id)
                        },
                    )
                }
            }
        }
        Spacer(Modifier.height(20.dp))
        KeelButton(
            label = "Add person",
            onClick = {
                if (name.isBlank()) return@KeelButton
                scope.launch {
                    viewModel.repository.createPerson(
                        orgId = orgId,
                        name = name,
                        roleTitle = role,
                        notes = notes,
                        phones = if (phone.isBlank()) emptyList() else listOf("mobile" to phone),
                        emails = if (email.isBlank()) emptyList() else listOf("work" to email),
                        teamIds = teamIds.toList(),
                    )
                    onDismiss()
                }
            },
            enabled = name.isNotBlank(),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CreateTeamForm(
    viewModel: KeelViewModel,
    orgId: String,
    people: List<com.keel.manager.data.Person>,
    onDismiss: () -> Unit,
) {
    var name by remember { mutableStateOf("") }
    var colorHex by remember { mutableStateOf(KeelColors.TeamPresets[0].let { "#E5604D" }) }
    var leaderId by remember { mutableStateOf<String?>(null) }
    val memberIds = remember { mutableStateListOf<String>() }
    val scope = rememberCoroutineScope()

    KeelSheet(onDismiss = onDismiss) {
        Text("New team", style = KeelType.Title, color = MaterialTheme.colorScheme.onSurface)
        Spacer(Modifier.height(16.dp))
        KeelTextField(value = name, onValueChange = { name = it }, placeholder = "Team name")
        Spacer(Modifier.height(16.dp))
        Text("Colour", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            for (preset in KeelColors.TeamPresets) {
                val hex = String.format("#%06X", 0xFFFFFF and preset.value.toInt())
                val selected = colorHex.equals(hex, ignoreCase = true)
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .clip(CircleShape)
                        .background(preset)
                        .then(keelClickable(onClick = { colorHex = hex })),
                    contentAlignment = Alignment.Center,
                ) {
                    if (selected) {
                        Box(
                            Modifier
                                .size(14.dp)
                                .clip(CircleShape)
                                .background(Color.White),
                        )
                    }
                }
            }
        }
        if (people.isEmpty()) {
            Spacer(Modifier.height(16.dp))
            Text(
                "A team needs a leader. Add a person first.",
                style = KeelType.Body,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        } else {
            Spacer(Modifier.height(16.dp))
            Text("Leader (required)", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
            androidx.compose.foundation.layout.FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                for (p in people) {
                    KeelChip(
                        label = p.name,
                        selected = leaderId == p.id,
                        onClick = {
                            leaderId = p.id
                            if (!memberIds.contains(p.id)) memberIds.add(p.id)
                        },
                    )
                }
            }
            Spacer(Modifier.height(16.dp))
            Text("Members", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
            androidx.compose.foundation.layout.FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                for (p in people) {
                    KeelChip(
                        label = p.name,
                        selected = memberIds.contains(p.id),
                        onClick = {
                            if (p.id == leaderId) return@KeelChip // leader is always a member
                            if (memberIds.contains(p.id)) memberIds.remove(p.id) else memberIds.add(p.id)
                        },
                    )
                }
            }
        }
        Spacer(Modifier.height(20.dp))
        KeelButton(
            label = "Create team",
            onClick = {
                val leader = leaderId ?: return@KeelButton
                if (name.isBlank()) return@KeelButton
                scope.launch {
                    viewModel.repository.createTeam(
                        orgId = orgId,
                        name = name,
                        colorHex = colorHex,
                        leaderPersonId = leader,
                        memberIds = memberIds.toList(),
                    )
                    onDismiss()
                }
            },
            enabled = name.isNotBlank() && leaderId != null,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

// ---------------------------------------------------------------------------
// Organization switcher.
// ---------------------------------------------------------------------------

@Composable
fun OrgSwitcherSheet(viewModel: KeelViewModel, nav: KeelNav, onDismiss: () -> Unit) {
    val orgs by viewModel.organizations.collectAsState()
    val active by viewModel.activeOrg.collectAsState()
    var newName by remember { mutableStateOf("") }
    var newKind by remember { mutableStateOf("Studio") }
    var adding by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    KeelSheet(onDismiss = onDismiss) {
        Text("Organizations", style = KeelType.Title, color = MaterialTheme.colorScheme.onSurface)
        Spacer(Modifier.height(12.dp))
        for (org in orgs) {
            val selected = org.id == active?.id
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 8.dp)
                    .then(
                        keelClickable(onClick = {
                            viewModel.setActiveOrg(org)
                            onDismiss()
                        }),
                    ),
            ) {
                Box(
                    modifier = Modifier
                        .size(12.dp)
                        .clip(CircleShape)
                        .background(
                            if (selected) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.outline,
                        ),
                )
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(org.name, style = KeelType.BodySemibold, color = MaterialTheme.colorScheme.onSurface)
                    Text(org.kind, style = KeelType.Caption, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (selected) {
                    Text("Active", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.primary)
                }
            }
        }
        Spacer(Modifier.height(12.dp))
        if (!adding) {
            KeelButton(label = "Add organization", onClick = { adding = true }, primary = false, modifier = Modifier.fillMaxWidth())
        } else {
            KeelTextField(value = newName, onValueChange = { newName = it }, placeholder = "Organization name")
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (kind in listOf("Studio", "Company", "Club", "Family", "Other")) {
                    KeelChip(label = kind, selected = newKind == kind, onClick = { newKind = kind })
                }
            }
            Spacer(Modifier.height(12.dp))
            KeelButton(
                label = "Create",
                onClick = {
                    if (newName.isBlank()) return@KeelButton
                    scope.launch {
                        val org = viewModel.repository.createOrganization(newName, newKind)
                        viewModel.setActiveOrg(org)
                        onDismiss()
                    }
                },
                enabled = newName.isNotBlank(),
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Global search on Home.
// ---------------------------------------------------------------------------

@Composable
fun SearchSheet(viewModel: KeelViewModel, nav: KeelNav, onDismiss: () -> Unit) {
    val query by viewModel.searchQuery.collectAsState()
    val results by viewModel.searchResults.collectAsState()
    val teams by viewModel.teams.collectAsState()
    val tasks by viewModel.tasks.collectAsState()
    val teamMembers by viewModel.teamMembers.collectAsState()
    val taskAssignees by viewModel.taskAssignees.collectAsState()

    KeelSheet(onDismiss = onDismiss) {
        KeelTextField(
            value = query,
            onValueChange = { viewModel.searchQuery.value = it },
            placeholder = "Search tasks, people, teams",
            leadingIcon = {
                androidx.compose.material3.Icon(
                    androidx.compose.material.icons.Icons.Outlined.Search,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(20.dp),
                )
            },
        )
        Spacer(Modifier.height(16.dp))
        if (query.isBlank()) {
            Text("Type to search across this organization.", style = KeelType.Body, color = MaterialTheme.colorScheme.onSurfaceVariant)
            return@KeelSheet
        }
        if (results.tasks.isEmpty() && results.people.isEmpty() && results.teams.isEmpty()) {
            Text("No matches for \"$query\".", style = KeelType.Body, color = MaterialTheme.colorScheme.onSurfaceVariant)
            return@KeelSheet
        }
        for (task in results.tasks) {
            val team = teams.firstOrNull { t -> t.id == task.teamId }
            TaskTile(
                task = task,
                team = team,
                assignees = taskAssignees[task.id] ?: emptyList(),
                onTap = { onDismiss(); nav.taskSheetId = task.id },
                onChevron = { onDismiss(); nav.taskPageId = task.id },
                onToggleDone = { viewModel.toggleTaskDone(task) },
            )
            Spacer(Modifier.height(8.dp))
        }
        for (person in results.people) {
            PersonRow(
                person = person,
                teamColor = null,
                subtitle = person.roleTitle,
                onTap = { onDismiss(); nav.personSheetId = person.id },
                onChevron = { onDismiss(); nav.personPageId = person.id },
            )
            Spacer(Modifier.height(8.dp))
        }
        for (team in results.teams) {
            val teamTasks = tasks.filter { t -> t.teamId == team.id }
            val done = teamTasks.count { it.isDone }
            TeamCard(
                team = team,
                memberCount = teamMembers[team.id]?.size ?: 0,
                progress = if (teamTasks.isEmpty()) 0.0 else done.toDouble() / teamTasks.size,
                doneCount = done,
                totalCount = teamTasks.size,
                onTap = { onDismiss(); nav.teamSheetId = team.id },
                onChevron = { onDismiss(); nav.teamPageId = team.id },
            )
            Spacer(Modifier.height(8.dp))
        }
    }
}
