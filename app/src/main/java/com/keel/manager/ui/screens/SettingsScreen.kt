package com.keel.manager.ui.screens

import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.keel.manager.BuildConfig
import com.keel.manager.KeelNav
import com.keel.manager.Links
import com.keel.manager.R
import com.keel.manager.data.BackupService
import com.keel.manager.data.SeedData
import com.keel.manager.data.ThemeMode
import com.keel.manager.ui.KeelViewModel
import com.keel.manager.ui.components.KeelButton
import com.keel.manager.ui.components.KeelCard
import com.keel.manager.ui.components.KeelTextField
import com.keel.manager.ui.components.SegmentedControl
import com.keel.manager.ui.components.keelClickable
import com.keel.manager.ui.theme.KeelColors
import com.keel.manager.ui.theme.KeelRadii
import com.keel.manager.ui.theme.KeelType
import kotlinx.coroutines.launch

/** Settings: Profile, Organizations, Personalization, Appearance,
 * Utilities, Backup, About. */
@Composable
fun SettingsScreen(viewModel: KeelViewModel, nav: KeelNav) {
    val settings by viewModel.settings.collectAsState()
    val org by viewModel.activeOrg.collectAsState()
    val orgs by viewModel.organizations.collectAsState()
    val profile by viewModel.repository.watchProfile().collectAsState(initial = null)
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val listState = rememberLazyListState()

    val signal = nav.scrollTopSignal
    LaunchedEffect(signal) {
        if (signal > 0) listState.animateScrollToItem(0)
    }

    var profileName by remember(profile?.name) { mutableStateOf(profile?.name ?: "") }
    var profileRole by remember(profile?.role) { mutableStateOf(profile?.role ?: "") }
    var showSampleConfirm by remember { mutableStateOf(false) }
    var showClearCompletedConfirm by remember { mutableStateOf(false) }
    var showResetConfirm by remember { mutableStateOf(false) }
    var backupMessage by remember { mutableStateOf<String?>(null) }

    val exportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/zip"),
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            try {
                val bytes = BackupService.exportTo(context, viewModel.repository, uri)
                viewModel.settingsStore.setLastBackupAt(System.currentTimeMillis())
                backupMessage = "Backup saved (${bytes / 1024} KB)."
            } catch (e: Exception) {
                backupMessage = "Backup failed: ${e.message}"
            }
        }
    }
    val importLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument(),
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            try {
                val (data, photos) = BackupService.readBackup(context, uri)
                val error = viewModel.repository.validateBackup(data)
                if (error != null) {
                    backupMessage = error
                    return@launch
                }
                val summary = viewModel.repository.importAll(data)
                BackupService.restorePhotos(context, photos)
                // Point at the first restored org.
                val first = viewModel.repository.getOrganizations().firstOrNull()
                if (first != null) viewModel.settingsStore.setActiveOrgId(first.id)
                backupMessage = "Restored ${summary.orgs} orgs, ${summary.people} people, ${summary.teams} teams, ${summary.tasks} tasks."
            } catch (e: Exception) {
                backupMessage = "Restore failed: ${e.message}"
            }
        }
    }

    LaunchedEffect(backupMessage) {
        backupMessage?.let {
            Toast.makeText(context, it, Toast.LENGTH_LONG).show()
            backupMessage = null
        }
    }

    LazyColumn(
        state = listState,
        modifier = Modifier.fillMaxSize().padding(horizontal = 20.dp),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(top = 16.dp, bottom = 120.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Text("Settings", style = KeelType.Display, color = MaterialTheme.colorScheme.onSurface)
        }

        // -- Profile ------------------------------------------------------------
        item {
            SectionHeader("Profile")
            KeelCard {
                Column {
                    Text("Name", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(6.dp))
                    KeelTextField(value = profileName, onValueChange = { profileName = it }, placeholder = "Your name")
                    Spacer(Modifier.height(12.dp))
                    Text("Role", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(6.dp))
                    KeelTextField(value = profileRole, onValueChange = { profileRole = it }, placeholder = "Your role")
                    Spacer(Modifier.height(12.dp))
                    KeelButton(
                        label = "Save profile",
                        onClick = {
                            scope.launch { viewModel.repository.saveProfile(profileName, profileRole) }
                        },
                        enabled = profileName.isNotBlank(),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        }

        // -- Organizations --------------------------------------------------------
        item {
            SectionHeader("Organizations", actionLabel = "Manage") { nav.showOrgSwitcher = true }
            KeelCard {
                Column {
                    Text(
                        "Active: ${org?.name ?: "—"}",
                        style = KeelType.BodySemibold,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "${orgs.size} organization${if (orgs.size == 1) "" else "s"} — tap Manage to switch, add or rename.",
                        style = KeelType.Body,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        // -- Personalization --------------------------------------------------------
        item {
            SectionHeader("Personalization")
            KeelCard {
                Column {
                    Text("Accent colour", style = KeelType.BodySemibold, color = MaterialTheme.colorScheme.onSurface)
                    Spacer(Modifier.height(10.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        // Default (kit teal) + presets.
                        val options: List<Pair<String, Color?>> = listOf(
                            "Default" to null,
                        ) + KeelColors.TeamPresets.map { c ->
                            String.format("#%06X", 0xFFFFFF and c.value.toInt()) to c
                        }
                        for ((hex, color) in options) {
                            val selected = settings.accentHex == hex ||
                                (hex == "Default" && settings.accentHex == null)
                            Box(
                                modifier = Modifier
                                    .size(36.dp)
                                    .clip(CircleShape)
                                    .background(color ?: MaterialTheme.colorScheme.primary)
                                    .then(keelClickable(onClick = {
                                        viewModel.setAccentHex(if (hex == "Default") null else hex)
                                    })),
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
                }
            }
        }

        // -- Appearance -------------------------------------------------------------
        item {
            SectionHeader("Appearance")
            KeelCard {
                Column {
                    Text("Theme", style = KeelType.BodySemibold, color = MaterialTheme.colorScheme.onSurface)
                    Spacer(Modifier.height(8.dp))
                    SegmentedControl(
                        options = listOf("System", "Light", "Dark"),
                        selectedIndex = when (settings.themeMode) {
                            ThemeMode.SYSTEM -> 0
                            ThemeMode.LIGHT -> 1
                            ThemeMode.DARK -> 2
                        },
                        onSelected = {
                            viewModel.setThemeMode(
                                when (it) {
                                    1 -> ThemeMode.LIGHT
                                    2 -> ThemeMode.DARK
                                    else -> ThemeMode.SYSTEM
                                },
                            )
                        },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Spacer(Modifier.height(16.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Text size", style = KeelType.BodySemibold, color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.weight(1f))
                        Text("${(settings.textScale * 100).toInt()}%", style = KeelType.CaptionMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Slider(
                        value = settings.textScale,
                        onValueChange = { viewModel.setTextScale(it) },
                        valueRange = 0.8f..1.5f,
                        steps = 6,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Spacer(Modifier.height(8.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text("Reduce motion", style = KeelType.BodySemibold, color = MaterialTheme.colorScheme.onSurface)
                            Text("Simple fades instead of springs and slides.", style = KeelType.Caption, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Switch(
                            checked = settings.reduceMotion,
                            onCheckedChange = { viewModel.setReduceMotion(it) },
                            colors = SwitchDefaults.colors(
                                checkedThumbColor = Color.White,
                                checkedTrackColor = MaterialTheme.colorScheme.primary,
                            ),
                        )
                    }
                }
            }
        }

        // -- Utilities --------------------------------------------------------------
        item {
            SectionHeader("Utilities")
            KeelCard {
                Column {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text("Daily digest", style = KeelType.BodySemibold, color = MaterialTheme.colorScheme.onSurface)
                            Text(
                                if (settings.remindersOn) "Every day at ${"%02d".format(settings.digestHour)}:${"%02d".format(settings.digestMinute)}"
                                else "A short summary of open and overdue tasks.",
                                style = KeelType.Caption,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Switch(
                            checked = settings.remindersOn,
                            onCheckedChange = { viewModel.setReminders(it, settings.digestHour, settings.digestMinute) },
                            colors = SwitchDefaults.colors(
                                checkedThumbColor = Color.White,
                                checkedTrackColor = MaterialTheme.colorScheme.primary,
                            ),
                        )
                    }
                    Spacer(Modifier.height(16.dp))
                    KeelButton(
                        label = "Load sample data",
                        onClick = { showSampleConfirm = true },
                        primary = false,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Spacer(Modifier.height(8.dp))
                    KeelButton(
                        label = "Clear completed tasks",
                        onClick = { showClearCompletedConfirm = true },
                        primary = false,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Spacer(Modifier.height(8.dp))
                    KeelButton(
                        label = "Reset all data",
                        onClick = { showResetConfirm = true },
                        primary = false,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        }

        // -- Backup ------------------------------------------------------------------
        item {
            SectionHeader("Backup")
            KeelCard {
                Column {
                    Text(
                        settings.lastBackupAt?.let { "Last backup: ${java.text.DateFormat.getDateTimeInstance().format(java.util.Date(it))}" }
                            ?: "No backup yet.",
                        style = KeelType.Body,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(12.dp))
                    KeelButton(
                        label = "Export backup",
                        onClick = {
                            val stamp = java.time.LocalDate.now().toString()
                            exportLauncher.launch("keel-backup-$stamp.keel")
                        },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Spacer(Modifier.height(8.dp))
                    KeelButton(
                        label = "Restore backup",
                        onClick = { importLauncher.launch(arrayOf("application/zip", "*/*")) },
                        primary = false,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "Backups are a zip with all your data and photos. Restoring replaces everything — the file is checked before anything is touched.",
                        style = KeelType.Caption,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        // -- About ---------------------------------------------------------------------
        item {
            KeelCard(onClick = { nav.showAbout = true }) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("About Keel", style = KeelType.BodySemibold, color = MaterialTheme.colorScheme.onSurface)
                        Text(
                            "Version ${BuildConfig.VERSION_NAME} · Offline, no account, no trackers.",
                            style = KeelType.Caption,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }

    if (showSampleConfirm) {
        ConfirmDialog(
            title = "Load sample data?",
            body = "Adds the Northwind Studio sample — 3 teams, 6 people, 6 tasks — to the active organization.",
            confirmLabel = "Load",
            onConfirm = {
                showSampleConfirm = false
                val id = org?.id ?: return@ConfirmDialog
                scope.launch { SeedData.load(viewModel.repository, id) }
            },
            onDismiss = { showSampleConfirm = false },
        )
    }
    if (showClearCompletedConfirm) {
        ConfirmDialog(
            title = "Clear completed tasks?",
            body = "Deletes every finished task in this organization. This cannot be undone.",
            confirmLabel = "Clear",
            onConfirm = {
                showClearCompletedConfirm = false
                val id = org?.id ?: return@ConfirmDialog
                scope.launch { viewModel.repository.clearCompletedTasks(id) }
            },
            onDismiss = { showClearCompletedConfirm = false },
        )
    }
    if (showResetConfirm) {
        ConfirmDialog(
            title = "Reset all data?",
            body = "Deletes every organization, person, team and task in Keel. This cannot be undone — export a backup first if you want to keep anything.",
            confirmLabel = "Reset everything",
            onConfirm = {
                showResetConfirm = false
                scope.launch {
                    // Delete every org (cascades to its data), then clear settings.
                    for (o in viewModel.repository.getOrganizations()) {
                        viewModel.repository.deleteOrganization(o.id)
                    }
                    viewModel.settingsStore.clearAll()
                }
            },
            onDismiss = { showResetConfirm = false },
        )
    }
}

/** About page: app identity + Developer card for Aby Bijo. */
@Composable
fun AboutPage(viewModel: KeelViewModel, nav: KeelNav) {
    val context = LocalContext.current
    Column(Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.surface)
                    .then(keelClickable(onClick = { nav.showAbout = false })),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back", tint = MaterialTheme.colorScheme.onSurface)
            }
            Spacer(Modifier.width(12.dp))
            Text("About", style = KeelType.Title, color = MaterialTheme.colorScheme.onSurface)
        }
        Spacer(Modifier.height(24.dp))
        androidx.compose.foundation.lazy.LazyColumn(
            verticalArrangement = Arrangement.spacedBy(12.dp),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 120.dp),
        ) {
            item {
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                    Box(
                        modifier = Modifier
                            .size(92.dp)
                            .clip(RoundedCornerShape(KeelRadii.IconTile))
                            .background(
                                Brush.linearGradient(
                                    listOf(KeelColors.TealGradientTop, KeelColors.TealGradientBottom),
                                ),
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            painterResource(R.drawable.ic_anchor),
                            contentDescription = "Keel",
                            tint = Color.White,
                            modifier = Modifier.size(50.dp),
                        )
                    }
                    Spacer(Modifier.height(16.dp))
                    Text("Keel", style = KeelType.Display, color = MaterialTheme.colorScheme.onSurface)
                    Text(
                        "Your work, in order.",
                        style = KeelType.Body,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "Version ${BuildConfig.VERSION_NAME} · ${BuildConfig.APPLICATION_ID}",
                        style = KeelType.Caption,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            item {
                KeelCard {
                    Column {
                        Text("Developer", style = KeelType.SectionTitle, color = MaterialTheme.colorScheme.onSurface)
                        Spacer(Modifier.height(4.dp))
                        Text(Links.DEVELOPER_NAME, style = KeelType.BodySemibold, color = MaterialTheme.colorScheme.onSurface)
                        Text(Links.DEVELOPER_ROLE, style = KeelType.Body, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.height(16.dp))
                        KeelButton(
                            label = "GitHub",
                            onClick = { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(Links.GITHUB))) },
                            primary = false,
                            modifier = Modifier.fillMaxWidth(),
                        )
                        Spacer(Modifier.height(8.dp))
                        KeelButton(
                            label = "LinkedIn",
                            onClick = { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(Links.LINKEDIN))) },
                            primary = false,
                            modifier = Modifier.fillMaxWidth(),
                        )
                        Spacer(Modifier.height(8.dp))
                        KeelButton(
                            label = "Buy Me a Coffee",
                            onClick = { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(Links.BUY_ME_A_COFFEE))) },
                            primary = false,
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
            }
            item {
                KeelCard {
                    Column {
                        Text("Privacy", style = KeelType.SectionTitle, color = MaterialTheme.colorScheme.onSurface)
                        Spacer(Modifier.height(4.dp))
                        Text(
                            "Keel is offline. There is no account, no server and no analytics. Everything you enter stays on this phone, in its own database, until you export or delete it.",
                            style = KeelType.Body,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}
