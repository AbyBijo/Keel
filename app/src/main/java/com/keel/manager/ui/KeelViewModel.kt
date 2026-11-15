package com.keel.manager.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.keel.manager.KeelApp
import com.keel.manager.data.AppSettings
import com.keel.manager.data.DeleteSnapshot
import com.keel.manager.data.HomeStats
import com.keel.manager.data.KeelRepository
import com.keel.manager.data.Organization
import com.keel.manager.data.Person
import com.keel.manager.data.SearchResults
import com.keel.manager.data.SettingsStore
import com.keel.manager.data.Task
import com.keel.manager.data.Team
import com.keel.manager.data.ThemeMode
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/** One undoable action shown in the snackbar for 6 seconds (rule 10). */
data class UndoState(val message: String, val snapshot: DeleteSnapshot)

/**
 * Single ViewModel for the whole app. Screens read StateFlows; every
 * mutation goes through the repository and is saved immediately.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class KeelViewModel(application: Application) : AndroidViewModel(application) {
    private val container = (application as KeelApp).container
    val repository: KeelRepository = container.repository
    val settingsStore: SettingsStore = container.settingsStore

    val settings: StateFlow<AppSettings> = settingsStore.settings
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), AppSettings())

    val organizations: StateFlow<List<Organization>> = repository.watchOrganizations()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    /** The active organization: the saved one, or the first one, or null. */
    val activeOrg: StateFlow<Organization?> = combine(settings, organizations) { s, orgs ->
        orgs.firstOrNull { it.id == s.activeOrgId } ?: orgs.firstOrNull()
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    private val activeOrgId: StateFlow<String?> = activeOrg
        .flatMapLatest { flowOf(it?.id) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    val tasks: StateFlow<List<Task>> = activeOrgId.flatMapLatest { id ->
        if (id == null) flowOf(emptyList()) else repository.watchTasks(id)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val people: StateFlow<List<Person>> = activeOrgId.flatMapLatest { id ->
        if (id == null) flowOf(emptyList()) else repository.watchPeople(id)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val teams: StateFlow<List<Team>> = activeOrgId.flatMapLatest { id ->
        if (id == null) flowOf(emptyList()) else repository.watchTeams(id)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    /** Stats are derived from the tasks flow — one source of truth. */
    val stats: StateFlow<HomeStats> = combine(tasks) { arr ->
        val list = arr[0] as List<Task>
        HomeStats(
            total = list.size,
            done = list.count { t -> t.isDone },
            overdue = list.count { t -> com.keel.manager.data.isOverdue(t) },
            dueSoon = list.count { t -> com.keel.manager.data.isDueSoon(t) },
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), HomeStats(0, 0, 0, 0))

    /** Team id -> members (for member counts and avatars). */
    val teamMembers: StateFlow<Map<String, List<Person>>> = teams.flatMapLatest { list ->
        kotlinx.coroutines.flow.flow {
            val map = mutableMapOf<String, List<Person>>()
            for (t in list) map[t.id] = repository.getTeamMembers(t.id)
            emit(map)
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyMap())

    /** Task id -> assignees (for tiles and sheets). */
    val taskAssignees: StateFlow<Map<String, List<Person>>> = tasks.flatMapLatest { list ->
        kotlinx.coroutines.flow.flow {
            val map = mutableMapOf<String, List<Person>>()
            for (t in list) map[t.id] = repository.getTaskAssignees(t.id)
            emit(map)
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyMap())

    /** Person id -> teams they belong to (for People rows). */
    val personTeams: StateFlow<Map<String, List<Team>>> = people.flatMapLatest { list ->
        kotlinx.coroutines.flow.flow {
            val map = mutableMapOf<String, List<Team>>()
            for (p in list) map[p.id] = repository.getTeamsForPerson(p.id)
            emit(map)
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyMap())

    val upNext: StateFlow<List<Task>> = combine(tasks) { arr ->
        val list = arr[0] as List<Task>
        val open = list.filter { !it.isDone }
        open.sortedWith(
            compareBy<Task> { if (com.keel.manager.data.isOverdue(it)) 0 else 1 }
                .thenBy { it.dueDate == null }
                .thenBy { it.dueDate ?: Long.MAX_VALUE },
        ).take(3)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    // -- search ---------------------------------------------------------------
    val searchQuery = MutableStateFlow("")
    val searchResults: StateFlow<SearchResults> = combine(searchQuery, activeOrg) { q, org ->
        if (q.isBlank() || org == null) SearchResults(emptyList(), emptyList(), emptyList())
        else repository.search(org.id, q)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), SearchResults(emptyList(), emptyList(), emptyList()))

    // -- undo snackbar ----------------------------------------------------------
    private val _undo = MutableStateFlow<UndoState?>(null)
    val undo: StateFlow<UndoState?> = _undo
    private var undoJob: Job? = null

    private fun showUndo(message: String, snapshot: DeleteSnapshot) {
        undoJob?.cancel()
        _undo.value = UndoState(message, snapshot)
        undoJob = viewModelScope.launch {
            delay(6_000)
            _undo.value = null
        }
    }

    fun undoDelete() {
        val state = _undo.value ?: return
        undoJob?.cancel()
        _undo.value = null
        viewModelScope.launch { repository.restoreSnapshot(state.snapshot) }
    }

    fun dismissUndo() {
        undoJob?.cancel()
        _undo.value = null
    }

    // -- mutations --------------------------------------------------------------
    fun toggleTaskDone(task: Task) {
        viewModelScope.launch { repository.setTaskDone(task.id, !task.isDone) }
    }

    fun deleteTask(task: Task) {
        viewModelScope.launch {
            val snap = repository.deleteTask(task.id)
            showUndo("Task deleted", snap)
        }
    }

    fun deletePerson(person: Person, leaderReplacements: Map<String, String> = emptyMap()) {
        viewModelScope.launch {
            val snap = repository.deletePerson(person.id, leaderReplacements)
            showUndo("Person deleted", snap)
        }
    }

    fun deleteTeam(team: Team) {
        viewModelScope.launch {
            val snap = repository.deleteTeam(team.id)
            showUndo("Team deleted — people and tasks kept", snap)
        }
    }

    fun setActiveOrg(org: Organization) {
        viewModelScope.launch { settingsStore.setActiveOrgId(org.id) }
    }

    fun setThemeMode(mode: ThemeMode) {
        viewModelScope.launch { settingsStore.setThemeMode(mode) }
    }

    fun setTextScale(scale: Float) {
        viewModelScope.launch { settingsStore.setTextScale(scale) }
    }

    fun setReduceMotion(value: Boolean) {
        viewModelScope.launch { settingsStore.setReduceMotion(value) }
    }

    fun setAccentHex(hex: String?) {
        viewModelScope.launch { settingsStore.setAccentHex(hex) }
    }

    fun setReminders(on: Boolean, hour: Int = 8, minute: Int = 0) {
        viewModelScope.launch {
            settingsStore.setRemindersOn(on)
            if (on) {
                settingsStore.setDigestTime(hour, minute)
                com.keel.manager.data.DigestScheduler.schedule(getApplication(), hour, minute)
            } else {
                com.keel.manager.data.DigestScheduler.cancel(getApplication())
            }
        }
    }
}
