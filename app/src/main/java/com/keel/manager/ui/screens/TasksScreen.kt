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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.PersonAdd
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
import com.keel.manager.data.isDueSoon
import com.keel.manager.data.isOverdue
import com.keel.manager.ui.KeelViewModel
import com.keel.manager.ui.components.EmptyState
import com.keel.manager.ui.components.KeelButton
import com.keel.manager.ui.components.KeelCard
import com.keel.manager.ui.components.KeelCheckbox
import com.keel.manager.ui.components.KeelChip
import com.keel.manager.ui.components.KeelTextField
import com.keel.manager.ui.components.LabelValueRow
import com.keel.manager.ui.components.keelClickable
import com.keel.manager.ui.theme.KeelType
import kotlinx.coroutines.launch

private enum class TaskFilter { ALL, OPEN, DONE, OVERDUE }

/** Tasks tab: filter chips + lazy list. Tap = overview sheet, chevron = page. */
@Composable
fun TasksScreen(viewModel: KeelViewModel, nav: KeelNav) {
    val tasks by viewModel.tasks.collectAsState()
    val teams by viewModel.teams.collectAsState()
    val taskAssignees by viewModel.taskAssignees.collectAsState()
    var filter by remember { mutableStateOf(TaskFilter.ALL) }
    val listState = rememberLazyListState()

    val signal = nav.scrollTopSignal
    LaunchedEffect(signal) {
        if (signal > 0) listState.animateScrollToItem(0)
    }

    val shown = when (filter) {
        TaskFilter.ALL -> tasks
        TaskFilter.OPEN -> tasks.filter { !it.isDone }
        TaskFilter.DONE -> tasks.filter { it.isDone }
        TaskFilter.OVERDUE -> tasks.filter { isOverdue(it) }
    }

    Column(Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 16.dp)) {
        Text("Tasks", style = KeelType.Display, color = MaterialTheme.colorScheme.onSurface)
        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (f in TaskFilter.entries) {
                val label = when (f) {
                    TaskFilter.ALL -> "All"
                    TaskFilter.OPEN -> "Open"
                    TaskFilter.DONE -> "Done"
                    TaskFilter.OVERDUE -> "Overdue"
                }
                KeelChip(label = label, selected = filter == f, onClick = { filter = f })
            }
        }
        Spacer(Modifier.height(12.dp))
        if (shown.isEmpty()) {
            EmptyState(
                title = when (filter) {
                    TaskFilter.ALL -> "No tasks yet"
                    TaskFilter.OPEN -> "No open tasks"
                    TaskFilter.DONE -> "Nothing done yet"
                    TaskFilter.OVERDUE -> "Nothing overdue"
                },
                body = when (filter) {
                    TaskFilter.ALL -> "Create your first task — give it a due date and people."
                    else -> "Try a different filter."
                },
                actionLabel = "Add a task",
                onAction = { nav.createKind = CreateKind.TASK },
            )
        } else {
            LazyColumn(
                state = listState,
                verticalArrangement = Arrangement.spacedBy(12.dp),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 120.dp),
            ) {
                items(shown, key = { it.id }) { task ->
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
        }
    }
}

/** Task overview sheet — quick buttons first, then the facts. */
@Composable
fun TaskOverviewSheet(viewModel: KeelViewModel, nav: KeelNav, taskId: String, onDismiss: () -> Unit) {
    val task by viewModel.repository.watchTask(taskId).collectAsState(initial = null)
    val teams by viewModel.teams.collectAsState()
    val assignees by viewModel.taskAssignees.collectAsState()
    val scope = rememberCoroutineScope()
    val current = task ?: return

    KeelSheet(onDismiss = onDismiss) {
        Text(current.title, style = KeelType.Title, color = MaterialTheme.colorScheme.onSurface)
        Spacer(Modifier.height(4.dp))
        val (label, labelColor) = dueLabel(current)
        Text(label, style = KeelType.CaptionMedium, color = labelColor)
        Spacer(Modifier.height(16.dp))
        // Quick actions: Complete, Edit, Delete.
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            KeelButton(
                label = if (current.isDone) "Reopen" else "Complete",
                onClick = {
                    viewModel.toggleTaskDone(current)
                    onDismiss()
                },
                leadingIcon = Icons.Outlined.Check,
                modifier = Modifier.weight(1f),
            )
            KeelButton(
                label = "Edit",
                onClick = {
                    onDismiss()
                    nav.taskPageId = current.id
                },
                leadingIcon = Icons.Outlined.Edit,
                primary = false,
                modifier = Modifier.weight(1f),
            )
            KeelButton(
                label = "Delete",
                onClick = {
                    viewModel.deleteTask(current)
                    onDismiss()
                },
                leadingIcon = Icons.Outlined.Delete,
                primary = false,
                modifier = Modifier.weight(1f),
            )
        }
        Spacer(Modifier.height(16.dp))
        val team = teams.firstOrNull { t -> t.id == current.teamId }
        LabelValueRow("Team", team?.name ?: "No team")
        Spacer(Modifier.height(8.dp))
        LabelValueRow("Priority", priorityLabel(current.priority))
        Spacer(Modifier.height(8.dp))
        LabelValueRow("Due", formatDueDate(current.dueDate))
        if (current.notes.isNotBlank()) {
            Spacer(Modifier.height(12.dp))
            Text(current.notes, style = KeelType.Body, color = MaterialTheme.colorScheme.onSurface)
        }
        val people = assignees[current.id] ?: emptyList()
        if (people.isNotEmpty()) {
            Spacer(Modifier.height(12.dp))
            Text("Assigned to", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(6.dp))
            for (p in people) {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(vertical = 2.dp)) {
                    Text(p.name, style = KeelType.Body, color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.weight(1f))
                    Text(
                        "Remove",
                        style = KeelType.CaptionMedium,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = keelClickable(onClick = {
                            scope.launch { viewModel.repository.unassignPersonFromTask(current.id, p.id) }
                        }),
                    )
                }
            }
        }
        Spacer(Modifier.height(8.dp))
        KeelButton(
            label = "Assign someone",
            onClick = { /* opens the assignee picker on the full page */ onDismiss(); nav.taskPageId = current.id },
            leadingIcon = Icons.Outlined.PersonAdd,
            primary = false,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/** Full task page: edit form + sub-todos + assignees. */
@Composable
fun TaskPage(viewModel: KeelViewModel, nav: KeelNav, taskId: String) {
    val task by viewModel.repository.watchTask(taskId).collectAsState(initial = null)
    val teams by viewModel.teams.collectAsState()
    val people by viewModel.people.collectAsState()
    val subs by viewModel.repository.watchSubTodos(taskId).collectAsState(initial = emptyList())
    val assignees by viewModel.taskAssignees.collectAsState()
    val scope = rememberCoroutineScope()
    val current = task ?: run {
        // Task was deleted while open — go back.
        LaunchedEffect(Unit) { nav.taskPageId = null }
        return
    }

    var title by remember(current.id) { mutableStateOf(current.title) }
    var notes by remember(current.id) { mutableStateOf(current.notes) }
    var priority by remember(current.id) { mutableStateOf(current.priority) }
    var teamId by remember(current.id) { mutableStateOf(current.teamId) }
    var newSub by remember { mutableStateOf("") }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    // Rule 7: when every sub-task is done, offer to complete the parent.
    var showCompleteOffer by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(androidx.compose.foundation.shape.CircleShape)
                    .background(MaterialTheme.colorScheme.surface)
                    .then(keelClickable(onClick = { nav.taskPageId = null })),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back", tint = MaterialTheme.colorScheme.onSurface)
            }
            Spacer(Modifier.width(12.dp))
            Text("Task", style = KeelType.Title, color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.weight(1f))
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
                Text("Title", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(6.dp))
                KeelTextField(value = title, onValueChange = { title = it }, placeholder = "Task title")
            }
            item {
                Text("Notes", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(6.dp))
                KeelTextField(value = notes, onValueChange = { notes = it }, placeholder = "Anything worth remembering", singleLine = false)
            }
            item {
                Text("Priority", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(6.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (p in listOf("none", "low", "medium", "high")) {
                        KeelChip(label = priorityLabel(p), selected = priority == p, onClick = { priority = p })
                    }
                }
            }
            item {
                Text("Team", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(6.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    KeelChip(label = "No team", selected = teamId == null, onClick = { teamId = null })
                    for (t in teams) {
                        KeelChip(label = t.name, selected = teamId == t.id, onClick = { teamId = t.id })
                    }
                }
            }
            item {
                KeelButton(
                    label = "Save changes",
                    onClick = {
                        scope.launch {
                            viewModel.repository.updateTask(
                                current.id,
                                title = title,
                                notes = notes,
                                priority = priority,
                                teamId = teamId,
                                teamIdSet = true,
                            )
                            nav.taskPageId = null
                        }
                    },
                    enabled = title.isNotBlank(),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            item {
                SectionHeader("Sub-tasks")
            }
            items(subs, key = { it.id }) { sub ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    KeelCheckbox(
                        checked = sub.isDone,
                        onCheckedChange = { done ->
                            scope.launch {
                                val result = viewModel.repository.toggleSubTodo(sub.id, done)
                                // Rule 7: all sub-tasks done -> OFFER to complete
                                // the parent (never auto-complete).
                                showCompleteOffer = result.allDone && !current.isDone
                            }
                        },
                    )
                    Spacer(Modifier.width(10.dp))
                    Text(
                        sub.title,
                        style = KeelType.Body,
                        color = if (sub.isDone) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.weight(1f),
                    )
                    Icon(
                        Icons.Outlined.Delete,
                        contentDescription = "Delete sub-task",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier
                            .size(24.dp)
                            .then(keelClickable(onClick = { scope.launch { viewModel.repository.deleteSubTodo(sub.id) } })),
                    )
                }
            }
            if (showCompleteOffer) {
                item {
                    KeelCard {
                        Column {
                            Text(
                                "All sub-tasks are done.",
                                style = KeelType.BodySemibold,
                                color = MaterialTheme.colorScheme.onSurface,
                            )
                            Spacer(Modifier.height(4.dp))
                            Text(
                                "Mark the whole task complete?",
                                style = KeelType.Body,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Spacer(Modifier.height(12.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                KeelButton(
                                    label = "Complete task",
                                    onClick = {
                                        showCompleteOffer = false
                                        viewModel.toggleTaskDone(current)
                                    },
                                    modifier = Modifier.weight(1f),
                                )
                                KeelButton(
                                    label = "Not yet",
                                    onClick = { showCompleteOffer = false },
                                    primary = false,
                                    modifier = Modifier.weight(1f),
                                )
                            }
                        }
                    }
                }
            }
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    KeelTextField(
                        value = newSub,
                        onValueChange = { newSub = it },
                        placeholder = "Add a sub-task",
                        modifier = Modifier.weight(1f),
                    )
                    Spacer(Modifier.width(8.dp))
                    Box(
                        modifier = Modifier
                            .size(44.dp)
                            .clip(androidx.compose.foundation.shape.CircleShape)
                            .background(MaterialTheme.colorScheme.primary)
                            .then(
                                keelClickable(onClick = {
                                    if (newSub.isBlank()) return@keelClickable
                                    scope.launch {
                                        viewModel.repository.addSubTodo(current.id, newSub)
                                        newSub = ""
                                    }
                                }),
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(Icons.Outlined.Add, contentDescription = "Add sub-task", tint = androidx.compose.ui.graphics.Color.White)
                    }
                }
            }
            item {
                SectionHeader("Assigned to")
            }
            items(assignees[current.id] ?: emptyList(), key = { it.id }) { p ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(p.name, style = KeelType.Body, color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.weight(1f))
                    Text(
                        "Remove",
                        style = KeelType.CaptionMedium,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = keelClickable(onClick = {
                            scope.launch { viewModel.repository.unassignPersonFromTask(current.id, p.id) }
                        }),
                    )
                }
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (p in people.filter { person -> (assignees[current.id] ?: emptyList()).none { it.id == person.id } }) {
                        KeelChip(label = "+ ${p.name}", selected = false, onClick = {
                            scope.launch { viewModel.repository.assignPersonToTask(current.id, p.id) }
                        })
                    }
                }
            }
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    KeelCheckbox(checked = current.isDone, onCheckedChange = { viewModel.toggleTaskDone(current) })
                    Spacer(Modifier.width(10.dp))
                    Text(
                        if (current.isDone) "Completed — tap to reopen" else "Mark complete",
                        style = KeelType.Body,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                }
            }
        }
    }
    if (showDeleteConfirm) {
        ConfirmDialog(
            title = "Delete this task?",
            body = "You can undo it for 6 seconds after deleting.",
            confirmLabel = "Delete",
            onConfirm = {
                showDeleteConfirm = false
                nav.taskPageId = null
                viewModel.deleteTask(current)
            },
            onDismiss = { showDeleteConfirm = false },
        )
    }
}
