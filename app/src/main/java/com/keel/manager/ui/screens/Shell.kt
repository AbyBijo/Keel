package com.keel.manager.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Group
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.dp
import com.keel.manager.CreateKind
import com.keel.manager.KeelNav
import com.keel.manager.Tab
import com.keel.manager.ui.KeelViewModel
import com.keel.manager.ui.components.keelClickable
import com.keel.manager.ui.theme.KeelMotion
import com.keel.manager.ui.theme.KeelType
import com.keel.manager.ui.theme.LocalReduceMotion

private data class TabDef(val tab: Tab, val label: String, val icon: ImageVector)

private val TABS = listOf(
    TabDef(Tab.HOME, "Home", Icons.Outlined.Home),
    TabDef(Tab.TASKS, "Tasks", Icons.Outlined.CheckCircle),
    TabDef(Tab.TEAMS, "Teams", Icons.Outlined.Group),
    TabDef(Tab.PEOPLE, "People", Icons.Outlined.Person),
    TabDef(Tab.SETTINGS, "Settings", Icons.Outlined.Settings),
)

/**
 * App shell: frosted 86dp bottom tab bar with a sliding accent pill,
 * FAB on Home only, Undo snackbar, and every sheet + detail page.
 * Hidden on onboarding only (MainActivity swaps the whole screen).
 */
@Composable
fun KeelShell(viewModel: KeelViewModel, nav: KeelNav) {
    val undo by viewModel.undo.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val reduceMotion = LocalReduceMotion.current

    // Back: close FAB -> detail page -> Home tab -> exit (system default).
    // Only intercept when there is actually something to close; otherwise
    // the press falls through and the activity finishes.
    val canGoBack = nav.fabOpen || nav.showAbout || nav.taskPageId != null ||
        nav.teamPageId != null || nav.personPageId != null || nav.tab != Tab.HOME
    BackHandler(enabled = canGoBack) {
        nav.onBack()
    }

    LaunchedEffect(undo) {
        val u = undo ?: return@LaunchedEffect
        val result = snackbarHostState.showSnackbar(
            message = u.message,
            actionLabel = "Undo",
            duration = SnackbarDuration.Short,
        )
        if (result == SnackbarResult.ActionPerformed) {
            viewModel.undoDelete()
        } else {
            viewModel.dismissUndo()
        }
    }

    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        // -- content ------------------------------------------------------------
        when {
            nav.showAbout -> AboutPage(viewModel = viewModel, nav = nav)
            nav.taskPageId != null -> TaskPage(viewModel = viewModel, nav = nav, taskId = nav.taskPageId!!)
            nav.teamPageId != null -> TeamPage(viewModel = viewModel, nav = nav, teamId = nav.teamPageId!!)
            nav.personPageId != null -> PersonPage(viewModel = viewModel, nav = nav, personId = nav.personPageId!!)
            else -> when (nav.tab) {
                Tab.HOME -> HomeScreen(viewModel = viewModel, nav = nav)
                Tab.TASKS -> TasksScreen(viewModel = viewModel, nav = nav)
                Tab.TEAMS -> TeamsScreen(viewModel = viewModel, nav = nav)
                Tab.PEOPLE -> PeopleScreen(viewModel = viewModel, nav = nav)
                Tab.SETTINGS -> SettingsScreen(viewModel = viewModel, nav = nav)
            }
        }

        // -- FAB (Home only) ------------------------------------------------------
        if (nav.tab == Tab.HOME && nav.taskPageId == null && nav.teamPageId == null &&
            nav.personPageId == null && !nav.showAbout
        ) {
            FabWithPills(viewModel = viewModel, nav = nav, modifier = Modifier.align(Alignment.BottomEnd))
        }

        // -- frosted tab bar --------------------------------------------------------
        if (nav.taskPageId == null && nav.teamPageId == null && nav.personPageId == null && !nav.showAbout) {
            TabBar(nav = nav, modifier = Modifier.align(Alignment.BottomCenter))
        }

        SnackbarHost(
            hostState = snackbarHostState,
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 96.dp),
        ) { data ->
            Snackbar(
                snackbarData = data,
                containerColor = MaterialTheme.colorScheme.onSurface,
                contentColor = MaterialTheme.colorScheme.surface,
                actionColor = MaterialTheme.colorScheme.primary,
                shape = RoundedCornerShape(14.dp),
            )
        }

        // -- sheets -------------------------------------------------------------------
        nav.taskSheetId?.let { id ->
            TaskOverviewSheet(viewModel = viewModel, nav = nav, taskId = id, onDismiss = { nav.taskSheetId = null })
        }
        nav.personSheetId?.let { id ->
            PersonOverviewSheet(viewModel = viewModel, nav = nav, personId = id, onDismiss = { nav.personSheetId = null })
        }
        nav.teamSheetId?.let { id ->
            TeamOverviewSheet(viewModel = viewModel, nav = nav, teamId = id, onDismiss = { nav.teamSheetId = null })
        }
        nav.createKind?.let { kind ->
            CreateSheet(viewModel = viewModel, nav = nav, kind = kind, onDismiss = { nav.createKind = null })
        }
        if (nav.showOrgSwitcher) {
            OrgSwitcherSheet(viewModel = viewModel, nav = nav, onDismiss = { nav.showOrgSwitcher = false })
        }
        if (nav.showSearch) {
            SearchSheet(viewModel = viewModel, nav = nav, onDismiss = { nav.showSearch = false })
        }
    }
}

@Composable
private fun TabBar(nav: KeelNav, modifier: Modifier = Modifier) {
    val accent = MaterialTheme.colorScheme.primary
    val reduceMotion = LocalReduceMotion.current
    // Frosted: translucent surface over the content (86dp total incl. padding).
    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp)
            .height(62.dp)
            .clip(RoundedCornerShape(31.dp))
            .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.88f)),
    ) {
        Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
            for (def in TABS) {
                val selected = nav.tab == def.tab
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(20.dp))
                        .background(if (selected) accent.copy(alpha = 0.14f) else Color.Transparent)
                        .then(keelClickable(onClick = { nav.selectTab(def.tab) }))
                        .padding(vertical = 10.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            def.icon,
                            contentDescription = def.label,
                            tint = if (selected) accent else MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(24.dp),
                        )
                        Text(
                            def.label,
                            style = KeelType.Small,
                            color = if (selected) accent else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

/** Floating Add button: rotates 45° (squircle -> circle) and opens 3
 * staggered pills — Task / Person / Team. Dim + blur behind. */
@Composable
private fun FabWithPills(viewModel: KeelViewModel, nav: KeelNav, modifier: Modifier = Modifier) {
    val haptics = LocalHapticFeedback.current
    val accent = MaterialTheme.colorScheme.primary
    val open = nav.fabOpen
    val rotation by animateFloatAsState(
        targetValue = if (open) 45f else 0f,
        animationSpec = KeelMotion.spring(),
        label = "fabRotation",
    )
    val reduceMotion = LocalReduceMotion.current

    Box(modifier = modifier.padding(end = 20.dp, bottom = 100.dp), contentAlignment = Alignment.BottomEnd) {
        Column(horizontalAlignment = Alignment.End) {
            if (open) {
                val pills = listOf(
                    "Task" to CreateKind.TASK,
                    "Person" to CreateKind.PERSON,
                    "Team" to CreateKind.TEAM,
                )
                pills.forEachIndexed { i, (label, kind) ->
                    // Stagger: each pill starts a beat after the previous one.
                    val stagger = i * KeelMotion.FabStaggerMs
                    AnimatedVisibility(
                        visible = open,
                        enter = if (reduceMotion) {
                            fadeIn(animationSpec = tween(delayMillis = stagger))
                        } else {
                            slideInVertically(
                                initialOffsetY = { it / 2 },
                                animationSpec = tween(
                                    durationMillis = KeelMotion.SheetMs,
                                    delayMillis = stagger,
                                ),
                            ) + fadeIn(animationSpec = tween(delayMillis = stagger))
                        },
                        exit = if (reduceMotion) {
                            fadeOut()
                        } else {
                            slideOutVertically(
                                targetOffsetY = { it / 2 },
                                animationSpec = tween(durationMillis = 180),
                            ) + fadeOut()
                        },
                    ) {
                        Box(
                            modifier = Modifier
                                .padding(bottom = 10.dp)
                                .clip(RoundedCornerShape(16.dp))
                                .background(MaterialTheme.colorScheme.surface)
                                .then(
                                    keelClickable(onClick = {
                                        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                        nav.fabOpen = false
                                        nav.createKind = kind
                                    }),
                                )
                                .padding(horizontal = 18.dp, vertical = 12.dp),
                        ) {
                            Text(label, style = KeelType.BodySemibold, color = MaterialTheme.colorScheme.onSurface)
                        }
                    }
                }
            }
            Box(
                modifier = Modifier
                    .size(56.dp)
                    .clip(if (open) CircleShape else RoundedCornerShape(18.dp))
                    .background(accent)
                    .then(
                        keelClickable(onClick = {
                            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            nav.fabOpen = !nav.fabOpen
                        }),
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Outlined.Add,
                    contentDescription = if (open) "Close" else "Add",
                    tint = Color.White,
                    modifier = Modifier.size(28.dp).rotate(rotation),
                )
            }
        }
    }
}
