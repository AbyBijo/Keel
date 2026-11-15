package com.keel.manager.data

import androidx.room.withTransaction
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import org.json.JSONArray
import org.json.JSONObject

fun newId(): String = UUID.randomUUID().toString()

/** Thrown when removing a team leader without naming a replacement. */
class LeaderRemovalNeedsReplacement(val teamId: String) : Exception()

/** Thrown when a team would be left without a leader. */
class LeaderRequiredException(message: String) : Exception(message)

/** Thrown when a leader is not a member of their own team (rule 4). */
class LeaderNotMemberException(message: String) : Exception(message)

/** Result of toggling a sub-todo (rule 7). */
data class ToggleSubTodoResult(val allDone: Boolean, val parentReopened: Boolean)

/**
 * A deleted entity plus everything needed to put it back (Undo, rule 10).
 * In-memory only: the snackbar lives 6 seconds, so nothing is persisted.
 */
data class DeleteSnapshot(
    val kind: String, // "task" | "person" | "team"
    val task: Task? = null,
    val person: Person? = null,
    val team: Team? = null,
    val phones: List<PersonPhone> = emptyList(),
    val emails: List<PersonEmail> = emptyList(),
    val memberships: List<TeamMember> = emptyList(),
    val assignments: List<TaskAssignee> = emptyList(),
    val subTodos: List<SubTodo> = emptyList(),
    /** Team ids the deleted person led (leadership was handed over). */
    val ledTeamIds: List<String> = emptyList(),
    /** Task ids that belonged to a deleted team (tasks survive, teamId nulled). */
    val teamTaskIds: List<String> = emptyList(),
)

data class HomeStats(val total: Int, val done: Int, val overdue: Int, val dueSoon: Int)
data class SearchResults(val tasks: List<Task>, val people: List<Person>, val teams: List<Team>)
data class ImportSummary(val orgs: Int, val people: Int, val teams: Int, val tasks: Int)

/**
 * All data access + the 10 logic rules. The UI never touches the DB
 * directly; every change goes through here and is saved immediately.
 * No dispatcher switching here — Room suspend functions are main-safe
 * and callers (ViewModels) own the coroutine scope.
 */
class KeelRepository(val db: KeelDatabase) {
    private val dao get() = db.keelDao()

    // -- profile & organizations -------------------------------------------

    suspend fun getProfile(): Profile? = dao.getProfile()
    fun watchProfile(): Flow<Profile?> = dao.watchProfile()

    suspend fun saveProfile(name: String, role: String) {
        dao.upsertProfile(Profile(name = name.trim(), role = role.trim()))
    }

    suspend fun getOrganizations(): List<Organization> = dao.getOrganizations()
    fun watchOrganizations(): Flow<List<Organization>> = dao.watchOrganizations()

    suspend fun createOrganization(name: String, kind: String): Organization {
        val org = Organization(
            id = newId(),
            name = name.trim(),
            kind = kind,
            createdAt = System.currentTimeMillis(),
        )
        dao.insertOrganization(org)
        return org
    }

    suspend fun renameOrganization(orgId: String, name: String) {
        dao.renameOrganization(orgId, name.trim())
    }

    /** Deleting an organization deletes everything inside it — and ONLY
     * inside it. The UI must confirm first; there is no undo for this
     * one (it is explicit). Tasks are deleted through deleteTaskRows so
     * main-task pointers on surviving teams are cleared first. */
    suspend fun deleteOrganization(orgId: String) {
        db.withTransaction {
            for (task in dao.getTasks(orgId)) {
                deleteTaskRows(task.id)
            }
            for (team in dao.getTeams(orgId)) {
                dao.deleteTeamRow(team.id)
            }
            for (person in dao.getPeople(orgId)) {
                dao.deletePersonRow(person.id)
            }
            dao.deleteOrganizationRow(orgId)
        }
    }

    // -- people ---------------------------------------------------------------

    suspend fun getPeople(orgId: String): List<Person> = dao.getPeople(orgId)
    fun watchPeople(orgId: String): Flow<List<Person>> = dao.watchPeople(orgId)
    suspend fun getPerson(id: String): Person? = dao.getPerson(id)
    fun watchPerson(id: String): Flow<Person?> = dao.watchPerson(id)

    suspend fun createPerson(
        orgId: String,
        name: String,
        roleTitle: String,
        photoPath: String? = null,
        notes: String = "",
        phones: List<Pair<String, String>> = emptyList(),
        emails: List<Pair<String, String>> = emptyList(),
        teamIds: List<String> = emptyList(),
    ): Person {
        val person = Person(
            id = newId(),
            orgId = orgId,
            name = name.trim(),
            roleTitle = roleTitle.trim(),
            photoPath = photoPath,
            notes = notes,
            createdAt = System.currentTimeMillis(),
        )
        db.withTransaction {
            dao.insertPerson(person)
            for ((label, number) in phones) {
                dao.insertPhone(PersonPhone(newId(), person.id, label, number.trim()))
            }
            for ((label, address) in emails) {
                dao.insertEmail(PersonEmail(newId(), person.id, label, address.trim()))
            }
            for (teamId in teamIds) {
                dao.insertTeamMember(TeamMember(teamId, person.id))
            }
        }
        return person
    }

    suspend fun updatePerson(
        id: String,
        name: String? = null,
        roleTitle: String? = null,
        notes: String? = null,
        photoPath: String? = null,
        photoPathSet: Boolean = false,
    ) {
        val current = dao.getPerson(id) ?: return
        dao.updatePerson(
            current.copy(
                name = name?.trim() ?: current.name,
                roleTitle = roleTitle?.trim() ?: current.roleTitle,
                notes = notes ?: current.notes,
                photoPath = if (photoPathSet) photoPath else current.photoPath,
            ),
        )
    }

    suspend fun getPhones(personId: String): List<PersonPhone> = dao.getPhones(personId)
    fun watchPhones(personId: String): Flow<List<PersonPhone>> = dao.watchPhones(personId)
    suspend fun getEmails(personId: String): List<PersonEmail> = dao.getEmails(personId)
    fun watchEmails(personId: String): Flow<List<PersonEmail>> = dao.watchEmails(personId)

    suspend fun addPhone(personId: String, label: String, number: String) {
        dao.insertPhone(PersonPhone(newId(), personId, label, number.trim()))
    }

    suspend fun addEmail(personId: String, label: String, address: String) {
        dao.insertEmail(PersonEmail(newId(), personId, label, address.trim()))
    }

    suspend fun deletePhone(id: String) = dao.deletePhone(id)
    suspend fun deleteEmail(id: String) = dao.deleteEmail(id)

    /** Rule 10: deleting a person removes only their assignments and
     * memberships — never other people, teams or tasks. If they lead any
     * team, [leaderReplacements] must name a new leader per team id,
     * otherwise [LeaderRemovalNeedsReplacement] is thrown. */
    suspend fun deletePerson(
        personId: String,
        leaderReplacements: Map<String, String> = emptyMap(),
    ): DeleteSnapshot {
        val person = dao.getPerson(personId) ?: throw IllegalStateException("Person not found: $personId")
        val ledTeams = dao.getTeamsLedBy(personId)
        for (team in ledTeams) {
            if (!leaderReplacements.containsKey(team.id)) {
                throw LeaderRemovalNeedsReplacement(team.id)
            }
        }
        val snapshot = DeleteSnapshot(
            kind = "person",
            person = person,
            phones = dao.getPhones(personId),
            emails = dao.getEmails(personId),
            memberships = dao.getMemberships(personId),
            assignments = dao.getAssignments(personId),
            ledTeamIds = ledTeams.map { it.id },
        )
        db.withTransaction {
            for (team in ledTeams) {
                val replacement = leaderReplacements.getValue(team.id)
                dao.updateTeam(team.copy(leaderPersonId = replacement))
                // The new leader must be a member (rule 4).
                dao.insertTeamMember(TeamMember(team.id, replacement))
            }
            dao.deletePersonRow(personId)
        }
        return snapshot
    }

    // -- teams ----------------------------------------------------------------

    suspend fun getTeams(orgId: String): List<Team> = dao.getTeams(orgId)
    fun watchTeams(orgId: String): Flow<List<Team>> = dao.watchTeams(orgId)
    suspend fun getTeam(id: String): Team? = dao.getTeam(id)
    fun watchTeam(id: String): Flow<Team?> = dao.watchTeam(id)

    /** Rule 4: a team is created with exactly one leader, who must be a
     * member. The leader is added as a member automatically. */
    suspend fun createTeam(
        orgId: String,
        name: String,
        colorHex: String,
        leaderPersonId: String,
        memberIds: List<String> = emptyList(),
        mainTaskId: String? = null,
    ): Team {
        if (leaderPersonId.isEmpty()) {
            throw LeaderRequiredException("A team needs a leader.")
        }
        val team = Team(
            id = newId(),
            orgId = orgId,
            name = name.trim(),
            colorHex = colorHex,
            leaderPersonId = leaderPersonId,
            mainTaskId = mainTaskId,
            createdAt = System.currentTimeMillis(),
        )
        db.withTransaction {
            dao.insertTeam(team)
            val members = (memberIds + leaderPersonId).toSet()
            for (m in members) {
                dao.insertTeamMember(TeamMember(team.id, m))
            }
        }
        return team
    }

    suspend fun updateTeam(
        id: String,
        name: String? = null,
        colorHex: String? = null,
        leaderPersonId: String? = null,
    ) {
        if (leaderPersonId != null) {
            val isMember = dao.getMembership(id, leaderPersonId)
            if (isMember == null) {
                throw LeaderNotMemberException("The leader must be a team member.")
            }
        }
        val current = dao.getTeam(id) ?: return
        dao.updateTeam(
            current.copy(
                name = name?.trim() ?: current.name,
                colorHex = colorHex ?: current.colorHex,
                leaderPersonId = leaderPersonId ?: current.leaderPersonId,
            ),
        )
    }

    /** Rule 2: membership is one table, written from either side. */
    suspend fun addTeamMember(teamId: String, personId: String) {
        dao.insertTeamMember(TeamMember(teamId, personId))
    }

    /** Rule 4: removing the leader requires [newLeaderId]; otherwise throws. */
    suspend fun removeTeamMember(
        teamId: String,
        personId: String,
        newLeaderId: String? = null,
    ) {
        val team = dao.getTeam(teamId) ?: return
        if (team.leaderPersonId == personId) {
            if (newLeaderId.isNullOrEmpty()) {
                throw LeaderRemovalNeedsReplacement(teamId)
            }
            db.withTransaction {
                dao.updateTeam(team.copy(leaderPersonId = newLeaderId))
                dao.insertTeamMember(TeamMember(teamId, newLeaderId))
                dao.deleteTeamMember(teamId, personId)
            }
            return
        }
        dao.deleteTeamMember(teamId, personId)
    }

    suspend fun getTeamMembers(teamId: String): List<Person> {
        val rows = dao.getTeamMembers(teamId)
        val people = rows.mapNotNull { dao.getPerson(it.personId) }
        return people.sortedBy { it.name }
    }

    fun watchTeamMembers(teamId: String): Flow<List<TeamMember>> = dao.watchTeamMembers(teamId)

    suspend fun getTeamsForPerson(personId: String): List<Team> {
        val rows = dao.getMemberships(personId)
        return rows.mapNotNull { dao.getTeam(it.teamId) }
    }

    /** Rule 5: at most one main task per team — setting one clears the old. */
    suspend fun setMainTask(teamId: String, taskId: String?) {
        db.withTransaction {
            if (taskId != null) {
                val task = dao.getTask(taskId)
                if (task != null && task.teamId != teamId) {
                    // Re-assign the task to this team so "main task" is meaningful.
                    dao.setTaskTeam(taskId, teamId)
                }
            }
            dao.setMainTaskId(teamId, taskId)
        }
    }

    /** Rule 5: team progress = done tasks / all its tasks. */
    suspend fun teamProgress(teamId: String): Double {
        val tasks = dao.getTasksForTeam(teamId)
        if (tasks.isEmpty()) return 0.0
        return tasks.count { it.isDone }.toDouble() / tasks.size
    }

    /** Rule 10: deleting a team does NOT delete its people or tasks.
     * Its tasks keep existing with no team. */
    suspend fun deleteTeam(teamId: String): DeleteSnapshot {
        val team = dao.getTeam(teamId) ?: throw IllegalStateException("Team not found: $teamId")
        val members = dao.getTeamMembers(teamId)
        val tasks = dao.getTasksForTeam(teamId)
        val snapshot = DeleteSnapshot(
            kind = "team",
            team = team,
            memberships = members,
            teamTaskIds = tasks.map { it.id },
        )
        db.withTransaction {
            dao.nullTeamOnTasks(teamId)
            dao.deleteTeamRow(teamId)
        }
        return snapshot
    }

    // -- tasks ----------------------------------------------------------------

    suspend fun getTasks(orgId: String): List<Task> = dao.getTasks(orgId)
    fun watchTasks(orgId: String): Flow<List<Task>> = dao.watchTasks(orgId)
    suspend fun getTasksForTeam(teamId: String): List<Task> = dao.getTasksForTeam(teamId)
    fun watchTasksForTeam(teamId: String): Flow<List<Task>> = dao.watchTasksForTeam(teamId)
    suspend fun getTask(id: String): Task? = dao.getTask(id)
    fun watchTask(id: String): Flow<Task?> = dao.watchTask(id)

    suspend fun createTask(
        orgId: String,
        title: String,
        notes: String = "",
        dueDate: Long? = null,
        priority: String = "none",
        teamId: String? = null,
        assigneeIds: List<String> = emptyList(),
        subTodoTitles: List<String> = emptyList(),
    ): Task {
        val task = Task(
            id = newId(),
            orgId = orgId,
            title = title.trim(),
            notes = notes,
            dueDate = dueDate?.let { startOfDayMillis(it) },
            priority = priority,
            teamId = teamId,
            isDone = false,
            completedAt = null,
            createdAt = System.currentTimeMillis(),
        )
        db.withTransaction {
            dao.insertTask(task)
            for (a in assigneeIds) {
                dao.insertAssignee(TaskAssignee(task.id, a))
            }
            subTodoTitles.forEachIndexed { i, rawTitle ->
                val t = rawTitle.trim()
                if (t.isEmpty()) return@forEachIndexed
                dao.insertSubTodo(SubTodo(newId(), task.id, t, false, i))
            }
        }
        return task
    }

    suspend fun updateTask(
        id: String,
        title: String? = null,
        notes: String? = null,
        dueDate: Long? = null,
        dueDateSet: Boolean = false,
        priority: String? = null,
        teamId: String? = null,
        teamIdSet: Boolean = false,
    ) {
        val current = dao.getTask(id) ?: return
        dao.updateTask(
            current.copy(
                title = title?.trim() ?: current.title,
                notes = notes ?: current.notes,
                dueDate = if (dueDateSet) dueDate?.let { startOfDayMillis(it) } else current.dueDate,
                priority = priority ?: current.priority,
                teamId = if (teamIdSet) teamId else current.teamId,
            ),
        )
    }

    /** Rule 1: assignment is reflexive — one table, read from both sides. */
    suspend fun assignPersonToTask(taskId: String, personId: String) {
        dao.insertAssignee(TaskAssignee(taskId, personId))
    }

    suspend fun unassignPersonFromTask(taskId: String, personId: String) {
        dao.deleteAssignee(taskId, personId)
    }

    suspend fun getTaskAssignees(taskId: String): List<Person> {
        val rows = dao.getAssignees(taskId)
        return rows.mapNotNull { dao.getPerson(it.personId) }
    }

    fun watchTaskAssignees(taskId: String): Flow<List<TaskAssignee>> = dao.watchAssignees(taskId)

    suspend fun getTasksForPerson(personId: String): List<Task> {
        val rows = dao.getAssignments(personId)
        val tasks = rows.mapNotNull { dao.getTask(it.taskId) }
        return tasks.sortedWith(
            compareBy<Task> { it.dueDate == null }.thenBy { it.dueDate ?: Long.MAX_VALUE },
        )
    }

    /** Rule 7: completing a task sets completedAt; reopening clears it. */
    suspend fun setTaskDone(taskId: String, done: Boolean) {
        dao.setTaskDone(taskId, done, if (done) System.currentTimeMillis() else null)
    }

    suspend fun deleteTask(taskId: String): DeleteSnapshot {
        val task = dao.getTask(taskId) ?: throw IllegalStateException("Task not found: $taskId")
        val snapshot = DeleteSnapshot(
            kind = "task",
            task = task,
            assignments = dao.getAssignees(taskId),
            subTodos = dao.getSubTodos(taskId),
        )
        deleteTaskRows(taskId)
        return snapshot
    }

    private suspend fun deleteTaskRows(taskId: String) {
        // Clear "main task" pointers explicitly: the Teams <-> Tasks foreign
        // keys are circular, so Teams.mainTaskId has no FK (see Models.kt).
        // Never rely on the DB to clean this up.
        dao.clearMainTaskPointers(taskId)
        dao.deleteTaskRow(taskId)
    }

    /** Restore a snapshot taken by deleteTask / deletePerson / deleteTeam. */
    suspend fun restoreSnapshot(snap: DeleteSnapshot) {
        db.withTransaction {
            when (snap.kind) {
                "task" -> {
                    val task = snap.task ?: return@withTransaction
                    dao.insertTask(task)
                    for (a in snap.assignments) dao.insertAssignee(a)
                    for (s in snap.subTodos) dao.insertSubTodo(s)
                }
                "person" -> {
                    val person = snap.person ?: return@withTransaction
                    dao.insertPerson(person)
                    for (e in snap.phones) dao.insertPhone(e)
                    for (e in snap.emails) dao.insertEmail(e)
                    for (e in snap.memberships) dao.insertTeamMember(e)
                    for (e in snap.assignments) dao.insertAssignee(e)
                    // Leadership was handed to replacements at delete time;
                    // restoring the person does not silently take it back.
                }
                "team" -> {
                    val team = snap.team ?: return@withTransaction
                    dao.insertTeam(team)
                    for (e in snap.memberships) dao.insertTeamMember(e)
                    for (id in snap.teamTaskIds) {
                        dao.setTaskTeam(id, team.id)
                    }
                }
            }
        }
    }

    suspend fun clearCompletedTasks(orgId: String): Int {
        val done = dao.getTasks(orgId).filter { it.isDone }
        for (t in done) {
            deleteTaskRows(t.id)
        }
        return done.size
    }

    // -- sub-todos --------------------------------------------------------------

    suspend fun getSubTodos(taskId: String): List<SubTodo> = dao.getSubTodos(taskId)
    fun watchSubTodos(taskId: String): Flow<List<SubTodo>> = dao.watchSubTodos(taskId)

    suspend fun addSubTodo(taskId: String, title: String): SubTodo {
        val existing = dao.getSubTodos(taskId)
        val sub = SubTodo(newId(), taskId, title.trim(), false, existing.size)
        dao.insertSubTodo(sub)
        return sub
    }

    /** Rule 7: toggling a sub-todo reports whether all sub-todos are now
     * done (so the UI can offer the inline "complete parent" prompt) and
     * whether the parent was reopened. */
    suspend fun toggleSubTodo(subTodoId: String, done: Boolean): ToggleSubTodoResult {
        val sub = dao.getSubTodo(subTodoId)
            ?: return ToggleSubTodoResult(allDone = false, parentReopened = false)
        var parentReopened = false
        db.withTransaction {
            dao.setSubTodoDone(subTodoId, done)
            if (!done) {
                // Reopening a sub-todo reopens the parent (rule 7).
                val parent = dao.getTask(sub.taskId)
                if (parent != null && parent.isDone) {
                    setTaskDone(parent.id, false)
                    parentReopened = true
                }
            }
        }
        val subs = dao.getSubTodos(sub.taskId)
        val allDone = subs.isNotEmpty() && subs.all { it.isDone }
        return ToggleSubTodoResult(allDone = allDone, parentReopened = parentReopened)
    }

    suspend fun deleteSubTodo(id: String) = dao.deleteSubTodo(id)

    suspend fun reorderSubTodos(taskId: String, orderedIds: List<String>) {
        db.withTransaction {
            orderedIds.forEachIndexed { i, id ->
                dao.setSubTodoOrder(id, i)
            }
        }
    }

    // -- search & stats ---------------------------------------------------------

    /** Global search on Home: tasks, people, teams in the active org. */
    suspend fun search(orgId: String, query: String): SearchResults {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return SearchResults(emptyList(), emptyList(), emptyList())
        val tasks = dao.getTasks(orgId).filter { it.title.lowercase().contains(q) }
        val people = dao.getPeople(orgId).filter { it.name.lowercase().contains(q) }
        val teams = dao.getTeams(orgId).filter { it.name.lowercase().contains(q) }
        // People also match by role, phone, email and team name.
        val extraPeople = mutableListOf<Person>()
        for (p in dao.getPeople(orgId)) {
            if (people.contains(p)) continue
            val hay = buildString {
                append(p.roleTitle)
                append(' ')
                append(dao.getPhones(p.id).joinToString(" ") { it.number })
                append(' ')
                append(dao.getEmails(p.id).joinToString(" ") { it.address })
                append(' ')
                append(getTeamsForPerson(p.id).joinToString(" ") { it.name })
            }.lowercase()
            if (hay.contains(q)) extraPeople.add(p)
        }
        return SearchResults(tasks, people + extraPeople, teams)
    }

    suspend fun homeStats(orgId: String, nowMillis: Long = System.currentTimeMillis()): HomeStats {
        val tasks = dao.getTasks(orgId)
        return HomeStats(
            total = tasks.size,
            done = tasks.count { it.isDone },
            overdue = tasks.count { isOverdue(it, nowMillis) },
            dueSoon = tasks.count { isDueSoon(it, nowMillis) },
        )
    }

    /** Up next: 2–3 most urgent open tasks — overdue first, then soonest due. */
    suspend fun upNext(orgId: String, limit: Int = 3, nowMillis: Long = System.currentTimeMillis()): List<Task> {
        val tasks = dao.getTasks(orgId).filter { !it.isDone }
        val sorted = tasks.sortedWith(
            compareBy<Task> { if (isOverdue(it, nowMillis)) 0 else 1 }
                .thenBy { it.dueDate == null }
                .thenBy { it.dueDate ?: Long.MAX_VALUE },
        )
        return sorted.take(limit)
    }

    // -- backup / restore -------------------------------------------------------

    /** Everything, as JSON, for backup. Photos are handled by the backup
     * service (files copied into the zip next to this JSON). */
    suspend fun exportAll(): JSONObject {
        fun <T> rows(list: List<T>, toJson: (T) -> JSONObject): JSONArray {
            val arr = JSONArray()
            for (e in list) arr.put(toJson(e))
            return arr
        }
        val profile = dao.getProfile()
        return JSONObject().apply {
            put("format", "keel-backup")
            put("version", 1)
            put("exportedAt", System.currentTimeMillis())
            put("organizations", rows(dao.getOrganizations()) { orgToJson(it) })
            if (profile != null) put("profile", profileToJson(profile))
            put("people", rows(dao.getAllPeople()) { personToJson(it) })
            put("phones", rows(dao.getAllPhones()) { phoneToJson(it) })
            put("emails", rows(dao.getAllEmails()) { emailToJson(it) })
            put("teams", rows(dao.getAllTeams()) { teamToJson(it) })
            put("teamMembers", rows(dao.getAllTeamMembers()) { memberToJson(it) })
            put("tasks", rows(dao.getAllTasks()) { taskToJson(it) })
            put("taskAssignees", rows(dao.getAllAssignees()) { assigneeToJson(it) })
            put("subTodos", rows(dao.getAllSubTodos()) { subTodoToJson(it) })
        }
    }

    /** Validate the file BEFORE replacing any data (see docs/security.md).
     * Returns null when the payload is valid, otherwise an error message. */
    fun validateBackup(data: JSONObject): String? {
        if (data.optString("format") != "keel-backup") {
            return "This file is not a Keel backup."
        }
        if (data.optInt("version", -1) != 1) {
            return "Unsupported backup version (${data.opt("version")})."
        }
        for (key in listOf("organizations", "people", "teams", "tasks", "taskAssignees", "teamMembers", "subTodos")) {
            if (data.opt(key) !is JSONArray) return "Backup is missing its $key list."
        }
        return null
    }

    /** Replace ALL data with a validated backup. Returns a summary. */
    suspend fun importAll(data: JSONObject): ImportSummary {
        val error = validateBackup(data)
        if (error != null) throw IllegalArgumentException(error)
        db.withTransaction {
            dao.clearSubTodos()
            dao.clearAssignees()
            dao.clearTasks()
            dao.clearTeamMembers()
            dao.clearTeams()
            dao.clearPhones()
            dao.clearEmails()
            dao.clearPeople()
            dao.clearOrganizations()
            dao.clearProfiles()

            val orgs = data.getJSONArray("organizations")
            for (i in 0 until orgs.length()) dao.insertOrganization(orgFromJson(orgs.getJSONObject(i)))
            if (data.has("profile") && !data.isNull("profile")) {
                dao.upsertProfile(profileFromJson(data.getJSONObject("profile")))
            }
            val people = data.getJSONArray("people")
            for (i in 0 until people.length()) dao.insertPerson(personFromJson(people.getJSONObject(i)))
            val phones = data.optJSONArray("phones") ?: JSONArray()
            for (i in 0 until phones.length()) dao.insertPhone(phoneFromJson(phones.getJSONObject(i)))
            val emails = data.optJSONArray("emails") ?: JSONArray()
            for (i in 0 until emails.length()) dao.insertEmail(emailFromJson(emails.getJSONObject(i)))
            val teams = data.getJSONArray("teams")
            for (i in 0 until teams.length()) dao.insertTeam(teamFromJson(teams.getJSONObject(i)))
            val members = data.getJSONArray("teamMembers")
            for (i in 0 until members.length()) dao.insertTeamMember(memberFromJson(members.getJSONObject(i)))
            val tasks = data.getJSONArray("tasks")
            for (i in 0 until tasks.length()) dao.insertTask(taskFromJson(tasks.getJSONObject(i)))
            val assignees = data.getJSONArray("taskAssignees")
            for (i in 0 until assignees.length()) dao.insertAssignee(assigneeFromJson(assignees.getJSONObject(i)))
            val subs = data.getJSONArray("subTodos")
            for (i in 0 until subs.length()) dao.insertSubTodo(subTodoFromJson(subs.getJSONObject(i)))
        }
        return ImportSummary(
            orgs = data.getJSONArray("organizations").length(),
            people = data.getJSONArray("people").length(),
            teams = data.getJSONArray("teams").length(),
            tasks = data.getJSONArray("tasks").length(),
        )
    }

    // -- JSON helpers -----------------------------------------------------------
    companion object {
        fun orgToJson(o: Organization) = JSONObject().apply {
            put("id", o.id); put("name", o.name); put("kind", o.kind); put("createdAt", o.createdAt)
        }
        fun orgFromJson(j: JSONObject) = Organization(j.getString("id"), j.getString("name"), j.getString("kind"), j.getLong("createdAt"))

        fun profileToJson(p: Profile) = JSONObject().apply {
            put("id", p.id); put("name", p.name); put("role", p.role)
        }
        fun profileFromJson(j: JSONObject) = Profile(j.optString("id", "profile"), j.getString("name"), j.getString("role"))

        fun personToJson(p: Person) = JSONObject().apply {
            put("id", p.id); put("orgId", p.orgId); put("name", p.name); put("roleTitle", p.roleTitle)
            put("photoPath", p.photoPath); put("notes", p.notes); put("createdAt", p.createdAt)
        }
        fun personFromJson(j: JSONObject) = Person(
            j.getString("id"), j.getString("orgId"), j.getString("name"), j.getString("roleTitle"),
            if (j.isNull("photoPath")) null else j.getString("photoPath"),
            j.optString("notes", ""), j.getLong("createdAt"),
        )

        fun phoneToJson(p: PersonPhone) = JSONObject().apply {
            put("id", p.id); put("personId", p.personId); put("label", p.label); put("number", p.number)
        }
        fun phoneFromJson(j: JSONObject) = PersonPhone(j.getString("id"), j.getString("personId"), j.getString("label"), j.getString("number"))

        fun emailToJson(e: PersonEmail) = JSONObject().apply {
            put("id", e.id); put("personId", e.personId); put("label", e.label); put("address", e.address)
        }
        fun emailFromJson(j: JSONObject) = PersonEmail(j.getString("id"), j.getString("personId"), j.getString("label"), j.getString("address"))

        fun teamToJson(t: Team) = JSONObject().apply {
            put("id", t.id); put("orgId", t.orgId); put("name", t.name); put("colorHex", t.colorHex)
            put("leaderPersonId", t.leaderPersonId); put("mainTaskId", t.mainTaskId); put("createdAt", t.createdAt)
        }
        fun teamFromJson(j: JSONObject) = Team(
            j.getString("id"), j.getString("orgId"), j.getString("name"), j.getString("colorHex"),
            j.getString("leaderPersonId"),
            if (j.isNull("mainTaskId")) null else j.getString("mainTaskId"),
            j.getLong("createdAt"),
        )

        fun memberToJson(m: TeamMember) = JSONObject().apply {
            put("teamId", m.teamId); put("personId", m.personId)
        }
        fun memberFromJson(j: JSONObject) = TeamMember(j.getString("teamId"), j.getString("personId"))

        fun taskToJson(t: Task) = JSONObject().apply {
            put("id", t.id); put("orgId", t.orgId); put("title", t.title); put("notes", t.notes)
            put("dueDate", t.dueDate); put("priority", t.priority); put("teamId", t.teamId)
            put("isDone", t.isDone); put("completedAt", t.completedAt); put("createdAt", t.createdAt)
        }
        fun taskFromJson(j: JSONObject) = Task(
            j.getString("id"), j.getString("orgId"), j.getString("title"), j.optString("notes", ""),
            if (j.isNull("dueDate")) null else j.getLong("dueDate"),
            j.optString("priority", "none"),
            if (j.isNull("teamId")) null else j.getString("teamId"),
            j.optBoolean("isDone", false),
            if (j.isNull("completedAt")) null else j.getLong("completedAt"),
            j.getLong("createdAt"),
        )

        fun assigneeToJson(a: TaskAssignee) = JSONObject().apply {
            put("taskId", a.taskId); put("personId", a.personId)
        }
        fun assigneeFromJson(j: JSONObject) = TaskAssignee(j.getString("taskId"), j.getString("personId"))

        fun subTodoToJson(s: SubTodo) = JSONObject().apply {
            put("id", s.id); put("taskId", s.taskId); put("title", s.title); put("isDone", s.isDone); put("sortOrder", s.sortOrder)
        }
        fun subTodoFromJson(j: JSONObject) = SubTodo(
            j.getString("id"), j.getString("taskId"), j.getString("title"),
            j.optBoolean("isDone", false), j.optInt("sortOrder", 0),
        )
    }
}
