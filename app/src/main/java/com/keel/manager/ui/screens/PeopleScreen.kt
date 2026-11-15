package com.keel.manager.ui.screens

import android.content.Intent
import android.net.Uri
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
import androidx.compose.material.icons.outlined.Call
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material.icons.automirrored.outlined.Message
import androidx.compose.material.icons.outlined.Search
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.keel.manager.CreateKind
import com.keel.manager.KeelNav
import com.keel.manager.ui.KeelViewModel
import com.keel.manager.ui.components.EmptyState
import com.keel.manager.ui.components.KeelButton
import com.keel.manager.ui.components.KeelTextField
import com.keel.manager.ui.components.LabelValueRow
import com.keel.manager.ui.components.PersonAvatar
import com.keel.manager.ui.components.keelClickable
import com.keel.manager.ui.theme.KeelType
import kotlinx.coroutines.launch

/** People tab: live search + rows. Tap = overview sheet, chevron = page. */
@Composable
fun PeopleScreen(viewModel: KeelViewModel, nav: KeelNav) {
    val people by viewModel.people.collectAsState()
    val personTeams by viewModel.personTeams.collectAsState()
    var query by remember { mutableStateOf("") }
    val listState = rememberLazyListState()

    val signal = nav.scrollTopSignal
    LaunchedEffect(signal) {
        if (signal > 0) listState.animateScrollToItem(0)
    }

    val shown = if (query.isBlank()) people else people.filter {
        it.name.contains(query, ignoreCase = true) || it.roleTitle.contains(query, ignoreCase = true)
    }

    Column(Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 16.dp)) {
        Text("People", style = KeelType.Display, color = MaterialTheme.colorScheme.onSurface)
        Spacer(Modifier.height(12.dp))
        KeelTextField(
            value = query,
            onValueChange = { query = it },
            placeholder = "Search people",
            leadingIcon = {
                Icon(
                    androidx.compose.material.icons.Icons.Outlined.Search,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(20.dp),
                )
            },
        )
        Spacer(Modifier.height(12.dp))
        if (shown.isEmpty()) {
            EmptyState(
                title = if (query.isBlank()) "No people yet" else "No matches",
                body = if (query.isBlank()) "Add the people you work with." else "Try a different search.",
                actionLabel = "Add a person",
                onAction = { nav.createKind = CreateKind.PERSON },
            )
        } else {
            LazyColumn(
                state = listState,
                verticalArrangement = Arrangement.spacedBy(12.dp),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 120.dp),
            ) {
                items(shown, key = { it.id }) { person ->
                    val teams = personTeams[person.id] ?: emptyList()
                    val firstColor = teams.firstOrNull()?.let { teamColor(it.colorHex) }
                    val subtitle = buildString {
                        append(person.roleTitle.ifBlank { "No role" })
                        if (teams.isNotEmpty()) {
                            append(" · ")
                            append(teams.joinToString(", ") { it.name })
                        }
                    }
                    PersonRow(
                        person = person,
                        teamColor = firstColor,
                        subtitle = subtitle,
                        onTap = { nav.personSheetId = person.id },
                        onChevron = { nav.personPageId = person.id },
                    )
                }
            }
        }
    }
}

/** Person overview sheet — Call sits bottom-right (right-thumb reach). */
@Composable
fun PersonOverviewSheet(viewModel: KeelViewModel, nav: KeelNav, personId: String, onDismiss: () -> Unit) {
    val person by viewModel.repository.watchPerson(personId).collectAsState(initial = null)
    val phones by viewModel.repository.watchPhones(personId).collectAsState(initial = emptyList())
    val emails by viewModel.repository.watchEmails(personId).collectAsState(initial = emptyList())
    val personTeams by viewModel.personTeams.collectAsState()
    val context = LocalContext.current
    val current = person ?: return
    val teams = personTeams[personId] ?: emptyList()
    val firstColor = teams.firstOrNull()?.let { teamColor(it.colorHex) }
    val firstPhone = phones.firstOrNull()?.number
    val firstEmail = emails.firstOrNull()?.address

    KeelSheet(onDismiss = onDismiss) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            PersonAvatar(name = current.name, teamColor = firstColor, size = 64.dp)
            Spacer(Modifier.width(16.dp))
            Column(Modifier.weight(1f)) {
                Text(current.name, style = KeelType.Title, color = MaterialTheme.colorScheme.onSurface)
                Text(
                    current.roleTitle.ifBlank { "No role" },
                    style = KeelType.Body,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (teams.isNotEmpty()) {
                    Text(
                        teams.joinToString(", ") { it.name },
                        style = KeelType.Caption,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
        Spacer(Modifier.height(20.dp))
        // Quick actions: Call is the primary, bottom-right action.
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            KeelButton(
                label = "Message",
                onClick = {
                    firstPhone?.let {
                        context.startActivity(Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$it")))
                    }
                    onDismiss()
                },
                leadingIcon = Icons.AutoMirrored.Outlined.Message,
                primary = false,
                modifier = Modifier.weight(1f),
            )
            KeelButton(
                label = "Email",
                onClick = {
                    firstEmail?.let {
                        context.startActivity(Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:$it")))
                    }
                    onDismiss()
                },
                leadingIcon = Icons.Outlined.Email,
                primary = false,
                modifier = Modifier.weight(1f),
            )
            // Call — right-most, the easiest right-thumb reach.
            KeelButton(
                label = "Call",
                onClick = {
                    firstPhone?.let {
                        context.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:$it")))
                    }
                    onDismiss()
                },
                leadingIcon = Icons.Outlined.Call,
                modifier = Modifier.weight(1f),
            )
        }
        Spacer(Modifier.height(16.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            KeelButton(
                label = "Open profile",
                onClick = { onDismiss(); nav.personPageId = current.id },
                primary = false,
                modifier = Modifier.weight(1f),
            )
            KeelButton(
                label = "Edit",
                onClick = { onDismiss(); nav.personPageId = current.id },
                leadingIcon = Icons.Outlined.Edit,
                primary = false,
                modifier = Modifier.weight(1f),
            )
            KeelButton(
                label = "Delete",
                onClick = {
                    viewModel.deletePerson(current)
                    onDismiss()
                },
                leadingIcon = Icons.Outlined.Delete,
                primary = false,
                modifier = Modifier.weight(1f),
            )
        }
        if (phones.isNotEmpty() || emails.isNotEmpty()) {
            Spacer(Modifier.height(16.dp))
            for (p in phones) {
                LabelValueRow(p.label.replaceFirstChar { it.uppercase() }, p.number)
                Spacer(Modifier.height(6.dp))
            }
            for (e in emails) {
                LabelValueRow(e.label.replaceFirstChar { it.uppercase() }, e.address)
                Spacer(Modifier.height(6.dp))
            }
        }
    }
}

/** Full person page: photo/camera badge, Call/Email/Message, phones, emails,
 * teams, tasks, notes. */
@Composable
fun PersonPage(viewModel: KeelViewModel, nav: KeelNav, personId: String) {
    val person by viewModel.repository.watchPerson(personId).collectAsState(initial = null)
    val phones by viewModel.repository.watchPhones(personId).collectAsState(initial = emptyList())
    val emails by viewModel.repository.watchEmails(personId).collectAsState(initial = emptyList())
    val personTeams by viewModel.personTeams.collectAsState()
    val tasks by viewModel.tasks.collectAsState()
    val taskAssignees by viewModel.taskAssignees.collectAsState()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val current = person ?: run {
        LaunchedEffect(Unit) { nav.personPageId = null }
        return
    }
    val teams = personTeams[personId] ?: emptyList()
    val firstColor = teams.firstOrNull()?.let { teamColor(it.colorHex) }
    val myTasks = tasks.filter { t -> (taskAssignees[t.id] ?: emptyList()).any { it.id == personId } }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf(false) }
    var editName by remember(current.id) { mutableStateOf(current.name) }
    var editRole by remember(current.id) { mutableStateOf(current.roleTitle) }
    var editNotes by remember(current.id) { mutableStateOf(current.notes) }
    var newPhone by remember { mutableStateOf("") }
    var newEmail by remember { mutableStateOf("") }

    Column(Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            androidx.compose.foundation.layout.Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(androidx.compose.foundation.shape.CircleShape)
                    .background(MaterialTheme.colorScheme.surface)
                    .then(keelClickable(onClick = { nav.personPageId = null })),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back", tint = MaterialTheme.colorScheme.onSurface)
            }
            Spacer(Modifier.width(12.dp))
            Text("Person", style = KeelType.Title, color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.weight(1f))
            Text(
                if (editing) "Done" else "Edit",
                style = KeelType.CaptionMedium,
                color = MaterialTheme.colorScheme.primary,
                modifier = keelClickable(onClick = {
                    if (editing) {
                        scope.launch {
                            viewModel.repository.updatePerson(current.id, name = editName, roleTitle = editRole, notes = editNotes)
                        }
                    }
                    editing = !editing
                }),
            )
            Spacer(Modifier.width(16.dp))
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
                Row(verticalAlignment = Alignment.CenterVertically) {
                    PersonAvatar(name = current.name, teamColor = firstColor, size = 72.dp)
                    Spacer(Modifier.width(16.dp))
                    Column(Modifier.weight(1f)) {
                        if (editing) {
                            KeelTextField(value = editName, onValueChange = { editName = it }, placeholder = "Name")
                            Spacer(Modifier.height(8.dp))
                            KeelTextField(value = editRole, onValueChange = { editRole = it }, placeholder = "Role")
                        } else {
                            Text(current.name, style = KeelType.Title, color = MaterialTheme.colorScheme.onSurface)
                            Text(current.roleTitle.ifBlank { "No role" }, style = KeelType.Body, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
            // Contact actions — Call on the right.
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    KeelButton(
                        label = "Message",
                        onClick = {
                            phones.firstOrNull()?.let {
                                context.startActivity(Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:${it.number}")))
                            }
                        },
                        leadingIcon = Icons.AutoMirrored.Outlined.Message,
                        primary = false,
                        modifier = Modifier.weight(1f),
                    )
                    KeelButton(
                        label = "Email",
                        onClick = {
                            emails.firstOrNull()?.let {
                                context.startActivity(Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:${it.address}")))
                            }
                        },
                        leadingIcon = Icons.Outlined.Email,
                        primary = false,
                        modifier = Modifier.weight(1f),
                    )
                    KeelButton(
                        label = "Call",
                        onClick = {
                            phones.firstOrNull()?.let {
                                context.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:${it.number}")))
                            }
                        },
                        leadingIcon = Icons.Outlined.Call,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
            if (phones.isNotEmpty() || emails.isNotEmpty()) {
                item { SectionHeader("Contact") }
                items(phones, key = { it.id }) { p ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("${p.label.replaceFirstChar { it.uppercase() }} · ${p.number}", style = KeelType.Body, color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.weight(1f))
                        Text("Remove", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.error,
                            modifier = keelClickable(onClick = { scope.launch { viewModel.repository.deletePhone(p.id) } }))
                    }
                }
                items(emails, key = { it.id }) { e ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("${e.label.replaceFirstChar { it.uppercase() }} · ${e.address}", style = KeelType.Body, color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.weight(1f))
                        Text("Remove", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.error,
                            modifier = keelClickable(onClick = { scope.launch { viewModel.repository.deleteEmail(e.id) } }))
                    }
                }
            }
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    KeelTextField(value = newPhone, onValueChange = { newPhone = it }, placeholder = "Add phone", keyboardType = androidx.compose.ui.text.input.KeyboardType.Phone, modifier = Modifier.weight(1f))
                    Spacer(Modifier.width(8.dp))
                    KeelButton(label = "Add", onClick = {
                        if (newPhone.isBlank()) return@KeelButton
                        scope.launch {
                            viewModel.repository.addPhone(current.id, "mobile", newPhone)
                            newPhone = ""
                        }
                    })
                }
            }
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    KeelTextField(value = newEmail, onValueChange = { newEmail = it }, placeholder = "Add email", keyboardType = androidx.compose.ui.text.input.KeyboardType.Email, modifier = Modifier.weight(1f))
                    Spacer(Modifier.width(8.dp))
                    KeelButton(label = "Add", onClick = {
                        if (newEmail.isBlank()) return@KeelButton
                        scope.launch {
                            viewModel.repository.addEmail(current.id, "work", newEmail)
                            newEmail = ""
                        }
                    })
                }
            }
            if (teams.isNotEmpty()) {
                item { SectionHeader("Teams") }
                items(teams, key = { it.id }) { t ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        androidx.compose.foundation.layout.Box(
                            Modifier
                                .size(10.dp)
                                .clip(androidx.compose.foundation.shape.CircleShape)
                                .background(teamColor(t.colorHex)),
                        )
                        Spacer(Modifier.width(10.dp))
                        Text(t.name, style = KeelType.Body, color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.weight(1f))
                        if (t.leaderPersonId == current.id) {
                            Text("Leader", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.primary)
                        } else {
                            Text("Leave", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.error,
                                modifier = keelClickable(onClick = {
                                    scope.launch { viewModel.repository.removeTeamMember(t.id, current.id) }
                                }))
                        }
                    }
                }
            }
            if (myTasks.isNotEmpty()) {
                item { SectionHeader("Tasks (${myTasks.size})") }
                items(myTasks, key = { it.id }) { t ->
                    TaskTile(
                        task = t,
                        team = null,
                        assignees = emptyList(),
                        onTap = { nav.taskSheetId = t.id },
                        onChevron = { nav.taskPageId = t.id },
                        onToggleDone = { viewModel.toggleTaskDone(t) },
                        showTeam = false,
                    )
                }
            }
            if (editing || current.notes.isNotBlank()) {
                item { SectionHeader("Notes") }
                item {
                    if (editing) {
                        KeelTextField(value = editNotes, onValueChange = { editNotes = it }, placeholder = "Notes", singleLine = false)
                    } else {
                        Text(current.notes, style = KeelType.Body, color = MaterialTheme.colorScheme.onSurface)
                    }
                }
            }
        }
    }
    if (showDeleteConfirm) {
        // Rule 4: if this person leads any team, a replacement must be picked.
        val ledTeams = teams.filter { it.leaderPersonId == current.id }
        ConfirmDialog(
            title = "Delete ${current.name}?",
            body = if (ledTeams.isEmpty()) {
                "Only their assignments and team memberships are removed. Teams and tasks stay."
            } else {
                "${current.name} leads ${ledTeams.joinToString(", ") { it.name }}. Pick a new leader for each team first — open the team page to change its leader."
            },
            confirmLabel = if (ledTeams.isEmpty()) "Delete" else "Got it",
            onConfirm = {
                showDeleteConfirm = false
                if (ledTeams.isEmpty()) {
                    nav.personPageId = null
                    scope.launch { viewModel.deletePerson(current) }
                }
            },
            onDismiss = { showDeleteConfirm = false },
        )
    }
}
