package com.keel.manager

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.keel.manager.ui.KeelViewModel
import com.keel.manager.ui.screens.KeelShell
import com.keel.manager.ui.screens.OnboardingScreen
import com.keel.manager.ui.theme.KeelTheme

enum class Tab { HOME, TASKS, TEAMS, PEOPLE, SETTINGS }

enum class CreateKind { TASK, PERSON, TEAM }

/** All navigation state for the app, held in one place. */
class KeelNav {
    var tab by mutableStateOf(Tab.HOME)
    var taskPageId by mutableStateOf<String?>(null)
    var teamPageId by mutableStateOf<String?>(null)
    var personPageId by mutableStateOf<String?>(null)
    var showAbout by mutableStateOf(false)
    var taskSheetId by mutableStateOf<String?>(null)
    var personSheetId by mutableStateOf<String?>(null)
    var teamSheetId by mutableStateOf<String?>(null)
    var createKind by mutableStateOf<CreateKind?>(null)
    var showOrgSwitcher by mutableStateOf(false)
    var showSearch by mutableStateOf(false)
    var fabOpen by mutableStateOf(false)
    /** Scroll-to-top signal for the active tab (tap active tab). */
    var scrollTopSignal by mutableStateOf(0)

    fun goHome() {
        tab = Tab.HOME
        taskPageId = null
        teamPageId = null
        personPageId = null
        showAbout = false
    }

    fun selectTab(next: Tab) {
        if (tab == next) {
            scrollTopSignal++
        } else {
            tab = next
        }
        taskPageId = null
        teamPageId = null
        personPageId = null
        showAbout = false
        fabOpen = false
    }

    /** Back behaviour: close FAB, then detail page, then Home tab, then exit. */
    fun onBack(): Boolean {
        if (fabOpen) {
            fabOpen = false
            return true
        }
        if (showAbout || taskPageId != null || teamPageId != null || personPageId != null) {
            showAbout = false
            taskPageId = null
            teamPageId = null
            personPageId = null
            return true
        }
        if (tab != Tab.HOME) {
            tab = Tab.HOME
            return true
        }
        return false
    }
}

class MainActivity : ComponentActivity() {
    private val viewModel: KeelViewModel by viewModels()
    private val nav = KeelNav()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            val settings by viewModel.settings.collectAsState()
            // In-app text scaling: system font scale x the user's setting.
            val density = androidx.compose.ui.platform.LocalDensity.current
            val scaledDensity = androidx.compose.ui.unit.Density(
                density = density.density,
                fontScale = density.fontScale * settings.textScale,
            )
            androidx.compose.runtime.CompositionLocalProvider(
                androidx.compose.ui.platform.LocalDensity provides scaledDensity,
            ) {
                KeelTheme(mode = settings.themeMode, reduceMotion = settings.reduceMotion) {
                    if (settings.onboardingDone) {
                        KeelShell(viewModel = viewModel, nav = nav)
                    } else {
                        OnboardingScreen(viewModel = viewModel)
                    }
                }
            }
        }
    }

}
