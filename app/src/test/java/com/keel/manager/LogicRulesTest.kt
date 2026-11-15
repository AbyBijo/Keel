package com.keel.manager

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.keel.manager.data.DeleteSnapshot
import com.keel.manager.data.KeelDatabase
import com.keel.manager.data.KeelRepository
import com.keel.manager.data.LeaderNotMemberException
import com.keel.manager.data.LeaderRemovalNeedsReplacement
import com.keel.manager.data.isDueSoon
import com.keel.manager.data.isOverdue
import com.keel.manager.data.startOfDayMillis
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.json.JSONObject
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Ports of the Flutter logic-rules tests (test/logic_rules_test.dart):
 * all 10 rules from the master prompt, plus backup validation +
 * export/import round-trip. Runs against an in-memory Room database
 * under Robolectric — no device, no Android SDK build needed.
 */
@RunWith(RobolectricTestRunner::class)
class LogicRulesTest {

    private lateinit var db: KeelDatabase
    private lateinit var repo: KeelRepository

    @Before
    fun setUp() {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            KeelDatabase::class.java,
        ).allowMainThreadQueries().build()
        repo = KeelRepository(db)
    }

    @After
    fun tearDown() {
        db.close()
    }

    private fun dayOffset(days: Long): Long =
        LocalDate.now(ZoneId.systemDefault()).plusDays(days)
            .atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()

    private suspend fun makeOrg(name: String = "Org") = repo.createOrganization(name, "Studio")

    private suspend fun makePerson(orgId: String, name: String) =
        repo.createPerson(orgId, name, "Member")

    // -- Rule 1: reflexive assignment -----------------------------------------

    @Test
    fun `rule 1 - assignment is reflexive through one table`() = runTest {
        val org = makeOrg()
        val person = makePerson(org.id, "Asha")
        val task = repo.createTask(org.id, "Write brief")
        repo.assignPersonToTask(task.id, person.id)

        assertEquals(listOf(person.id), repo.getTaskAssignees(task.id).map { it.id })
        assertEquals(listOf(task.id), repo.getTasksForPerson(person.id).map { it.id })

        repo.unassignPersonFromTask(task.id, person.id)
        assertTrue(repo.getTaskAssignees(task.id).isEmpty())
        assertTrue(repo.getTasksForPerson(person.id).isEmpty())
    }

    // -- Rule 2: many-to-many ---------------------------------------------------

    @Test
    fun `rule 2 - person in two teams, team has many members`() = runTest {
        val org = makeOrg()
        val a = makePerson(org.id, "A")
        val b = makePerson(org.id, "B")
        val c = makePerson(org.id, "C")
        val t1 = repo.createTeam(org.id, "Design", "#E5604D", a.id, listOf(b.id))
        val t2 = repo.createTeam(org.id, "Eng", "#4F6BED", b.id, listOf(a.id, c.id))

        assertEquals(setOf(t1.id, t2.id), repo.getTeamsForPerson(a.id).map { it.id }.toSet())
        assertEquals(setOf(a.id, b.id), repo.getTeamMembers(t1.id).map { it.id }.toSet())
        assertEquals(setOf(a.id, b.id, c.id), repo.getTeamMembers(t2.id).map { it.id }.toSet())
    }

    // -- Rule 3 / 6: task combinations ------------------------------------------

    @Test
    fun `rule 3 and 6 - task alone, team-only, people-only, both`() = runTest {
        val org = makeOrg()
        val person = makePerson(org.id, "Solo")
        val team = repo.createTeam(org.id, "Team", "#2E9C78", person.id)

        val alone = repo.createTask(org.id, "Alone")
        val teamOnly = repo.createTask(org.id, "Team only", teamId = team.id)
        val peopleOnly = repo.createTask(org.id, "People only", assigneeIds = listOf(person.id))
        val both = repo.createTask(org.id, "Both", teamId = team.id, assigneeIds = listOf(person.id))

        assertNull(alone.teamId)
        assertTrue(repo.getTaskAssignees(alone.id).isEmpty())
        assertEquals(team.id, teamOnly.teamId)
        assertTrue(repo.getTaskAssignees(teamOnly.id).isEmpty())
        assertNull(peopleOnly.teamId)
        assertEquals(listOf(person.id), repo.getTaskAssignees(peopleOnly.id).map { it.id })
        assertEquals(team.id, both.teamId)
        assertEquals(listOf(person.id), repo.getTaskAssignees(both.id).map { it.id })
    }

    // -- Rule 4: exactly one leader ---------------------------------------------

    @Test
    fun `rule 4 - leader is auto-added as a member`() = runTest {
        val org = makeOrg()
        val leader = makePerson(org.id, "Lead")
        val team = repo.createTeam(org.id, "T", "#E5604D", leader.id)
        assertEquals(listOf(leader.id), repo.getTeamMembers(team.id).map { it.id })
    }

    @Test
    fun `rule 4 - leader cannot be a non-member`() = runTest {
        val org = makeOrg()
        val a = makePerson(org.id, "A")
        val outsider = makePerson(org.id, "Outsider")
        val team = repo.createTeam(org.id, "T", "#E5604D", a.id)
        try {
            repo.updateTeam(team.id, leaderPersonId = outsider.id)
            fail("Expected LeaderNotMemberException")
        } catch (e: LeaderNotMemberException) {
            // expected
        }
    }

    @Test
    fun `rule 4 - removing leader without replacement throws`() = runTest {
        val org = makeOrg()
        val a = makePerson(org.id, "A")
        val b = makePerson(org.id, "B")
        val team = repo.createTeam(org.id, "T", "#E5604D", a.id, listOf(b.id))
        try {
            repo.removeTeamMember(team.id, a.id)
            fail("Expected LeaderRemovalNeedsReplacement")
        } catch (e: LeaderRemovalNeedsReplacement) {
            assertEquals(team.id, e.teamId)
        }
        // With a replacement it works, and the old leader leaves the team.
        repo.removeTeamMember(team.id, a.id, newLeaderId = b.id)
        val updated = repo.getTeam(team.id)!!
        assertEquals(b.id, updated.leaderPersonId)
        assertFalse(repo.getTeamMembers(team.id).any { it.id == a.id })
    }

    @Test
    fun `rule 4 - deleting a leader needs a replacement`() = runTest {
        val org = makeOrg()
        val a = makePerson(org.id, "A")
        val b = makePerson(org.id, "B")
        val team = repo.createTeam(org.id, "T", "#E5604D", a.id, listOf(b.id))
        try {
            repo.deletePerson(a.id)
            fail("Expected LeaderRemovalNeedsReplacement")
        } catch (e: LeaderRemovalNeedsReplacement) {
            assertEquals(team.id, e.teamId)
        }
        repo.deletePerson(a.id, mapOf(team.id to b.id))
        assertEquals(b.id, repo.getTeam(team.id)!!.leaderPersonId)
        assertNull(repo.getPerson(a.id))
    }

    // -- Rule 5: main task + progress -------------------------------------------

    @Test
    fun `rule 5 - at most one main task per team`() = runTest {
        val org = makeOrg()
        val person = makePerson(org.id, "P")
        val team = repo.createTeam(org.id, "T", "#E5604D", person.id)
        val t1 = repo.createTask(org.id, "One", teamId = team.id)
        val t2 = repo.createTask(org.id, "Two", teamId = team.id)
        repo.setMainTask(team.id, t1.id)
        assertEquals(t1.id, repo.getTeam(team.id)!!.mainTaskId)
        repo.setMainTask(team.id, t2.id)
        assertEquals(t2.id, repo.getTeam(team.id)!!.mainTaskId)
        repo.setMainTask(team.id, null)
        assertNull(repo.getTeam(team.id)!!.mainTaskId)
    }

    @Test
    fun `rule 5 - team progress is done over all tasks`() = runTest {
        val org = makeOrg()
        val person = makePerson(org.id, "P")
        val team = repo.createTeam(org.id, "T", "#E5604D", person.id)
        assertEquals(0.0, repo.teamProgress(team.id), 0.001)
        val t1 = repo.createTask(org.id, "One", teamId = team.id)
        repo.createTask(org.id, "Two", teamId = team.id)
        repo.setTaskDone(t1.id, true)
        assertEquals(0.5, repo.teamProgress(team.id), 0.001)
    }

    // -- Rule 7: sub-todos -------------------------------------------------------

    @Test
    fun `rule 7 - all sub-todos done reports allDone`() = runTest {
        val org = makeOrg()
        val task = repo.createTask(org.id, "Parent", subTodoTitles = listOf("a", "b"))
        val subs = repo.getSubTodos(task.id)
        assertEquals(2, subs.size)
        val first = repo.toggleSubTodo(subs[0].id, true)
        assertFalse(first.allDone)
        val second = repo.toggleSubTodo(subs[1].id, true)
        assertTrue(second.allDone)
        // Parent is NOT auto-completed — the UI offers it.
        assertFalse(repo.getTask(task.id)!!.isDone)
    }

    @Test
    fun `rule 7 - reopening a sub-todo reopens the parent`() = runTest {
        val org = makeOrg()
        val task = repo.createTask(org.id, "Parent", subTodoTitles = listOf("a"))
        val sub = repo.getSubTodos(task.id).first()
        repo.toggleSubTodo(sub.id, true)
        repo.setTaskDone(task.id, true)
        assertTrue(repo.getTask(task.id)!!.isDone)
        val result = repo.toggleSubTodo(sub.id, false)
        assertTrue(result.parentReopened)
        assertFalse(repo.getTask(task.id)!!.isDone)
        assertNull(repo.getTask(task.id)!!.completedAt)
    }

    @Test
    fun `rule 7 - completing a task sets completedAt`() = runTest {
        val org = makeOrg()
        val task = repo.createTask(org.id, "T")
        assertNull(task.completedAt)
        repo.setTaskDone(task.id, true)
        assertNotNull(repo.getTask(task.id)!!.completedAt)
        repo.setTaskDone(task.id, false)
        assertNull(repo.getTask(task.id)!!.completedAt)
    }

    // -- Rule 8: overdue / due soon ----------------------------------------------

    @Test
    fun `rule 8 - overdue and due soon`() = runTest {
        val org = makeOrg()
        val overdue = repo.createTask(org.id, "Late", dueDate = dayOffset(-1))
        val soon = repo.createTask(org.id, "Soon", dueDate = dayOffset(1))
        val later = repo.createTask(org.id, "Later", dueDate = dayOffset(5))
        val doneLate = repo.createTask(org.id, "Done late", dueDate = dayOffset(-2))
        repo.setTaskDone(doneLate.id, true)

        assertTrue(isOverdue(repo.getTask(overdue.id)!!))
        assertFalse(isOverdue(repo.getTask(soon.id)!!))
        assertFalse(isOverdue(repo.getTask(doneLate.id)!!))
        assertTrue(isDueSoon(repo.getTask(soon.id)!!))
        assertFalse(isDueSoon(repo.getTask(later.id)!!))
        assertFalse(isDueSoon(repo.getTask(overdue.id)!!))
        // Due dates are normalized to start of day.
        assertEquals(startOfDayMillis(dayOffset(-1)), repo.getTask(overdue.id)!!.dueDate)
    }

    // -- Rule 9: org scoping ------------------------------------------------------

    @Test
    fun `rule 9 - everything is scoped to the active organization`() = runTest {
        val a = makeOrg("A")
        val b = makeOrg("B")
        val personA = makePerson(a.id, "In A")
        repo.createTask(a.id, "Task A")
        repo.createTeam(a.id, "Team A", "#E5604D", personA.id)
        makePerson(b.id, "In B")

        assertEquals(1, repo.getPeople(a.id).size)
        assertEquals(1, repo.getPeople(b.id).size)
        assertEquals(1, repo.getTasks(a.id).size)
        assertEquals(0, repo.getTasks(b.id).size)
        assertEquals(1, repo.getTeams(a.id).size)
        assertEquals(0, repo.getTeams(b.id).size)
        assertTrue(repo.search(b.id, "Task A").tasks.isEmpty())
        assertEquals(1, repo.search(a.id, "Task A").tasks.size)
    }

    // -- Rule 10: soft delete + restore --------------------------------------------

    @Test
    fun `rule 10 - delete and restore a task keeps assignments and sub-todos`() = runTest {
        val org = makeOrg()
        val person = makePerson(org.id, "P")
        val task = repo.createTask(
            org.id, "T",
            assigneeIds = listOf(person.id),
            subTodoTitles = listOf("x", "y"),
        )
        val snap = repo.deleteTask(task.id)
        assertNull(repo.getTask(task.id))
        assertTrue(repo.getSubTodos(task.id).isEmpty())
        repo.restoreSnapshot(snap)
        assertNotNull(repo.getTask(task.id))
        assertEquals(2, repo.getSubTodos(task.id).size)
        assertEquals(listOf(person.id), repo.getTaskAssignees(task.id).map { it.id })
    }

    @Test
    fun `rule 10 - deleting a person removes only assignments and memberships`() = runTest {
        val org = makeOrg()
        val person = makePerson(org.id, "P")
        val other = makePerson(org.id, "Other")
        val team = repo.createTeam(org.id, "T", "#E5604D", other.id, listOf(person.id))
        val task = repo.createTask(org.id, "T", assigneeIds = listOf(person.id, other.id))
        val snap = repo.deletePerson(person.id)
        assertNull(repo.getPerson(person.id))
        assertNotNull(repo.getTeam(team.id))
        assertNotNull(repo.getTask(task.id))
        assertEquals(listOf(other.id), repo.getTaskAssignees(task.id).map { it.id })
        assertFalse(repo.getTeamMembers(team.id).any { it.id == person.id })
        // Restore brings everything back.
        repo.restoreSnapshot(snap)
        assertNotNull(repo.getPerson(person.id))
        assertEquals(setOf(person.id, other.id), repo.getTaskAssignees(task.id).map { it.id }.toSet())
        assertTrue(repo.getTeamMembers(team.id).any { it.id == person.id })
    }

    @Test
    fun `rule 10 - deleting a team keeps people and tasks`() = runTest {
        val org = makeOrg()
        val person = makePerson(org.id, "P")
        val team = repo.createTeam(org.id, "T", "#E5604D", person.id)
        val task = repo.createTask(org.id, "T", teamId = team.id)
        repo.setMainTask(team.id, task.id)
        val snap: DeleteSnapshot = repo.deleteTeam(team.id)
        assertNull(repo.getTeam(team.id))
        assertNotNull(repo.getPerson(person.id))
        val kept = repo.getTask(task.id)!!
        assertNull(kept.teamId)
        // Restore re-links the task to the team.
        repo.restoreSnapshot(snap)
        assertNotNull(repo.getTeam(team.id))
        assertEquals(team.id, repo.getTask(task.id)!!.teamId)
        assertEquals(task.id, repo.getTeam(team.id)!!.mainTaskId)
    }

    // -- Backup ----------------------------------------------------------------------

    @Test
    fun `backup - validation rejects bad files and round-trip restores`() = runTest {
        val org = makeOrg()
        val person = makePerson(org.id, "P")
        repo.createTask(org.id, "T", assigneeIds = listOf(person.id))

        val exported = repo.exportAll()
        assertNull(repo.validateBackup(exported))

        val bad = JSONObject().apply { put("format", "something-else") }
        assertNotNull(repo.validateBackup(bad))

        // Round-trip: wipe, import, everything is back.
        repo.importAll(exported)
        assertEquals(1, repo.getOrganizations().size)
        assertEquals(1, repo.getPeople(org.id).size)
        assertEquals(1, repo.getTasks(org.id).size)
        assertEquals(listOf(person.id), repo.getTaskAssignees(repo.getTasks(org.id).first().id).map { it.id })
    }
}
