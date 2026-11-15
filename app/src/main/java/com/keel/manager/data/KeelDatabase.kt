package com.keel.manager.data

import android.content.Context
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.Update
import androidx.sqlite.db.SupportSQLiteDatabase
import kotlinx.coroutines.flow.Flow

// ---------------------------------------------------------------------------
// DAO — every query the repository needs. Inserts use REPLACE so restores
// (Undo) can re-insert a snapshot over a conflicting row.
// ---------------------------------------------------------------------------

@Dao
interface KeelDao {
    // -- profile & organizations -------------------------------------------
    @Query("SELECT * FROM profiles WHERE id = 'profile' LIMIT 1")
    suspend fun getProfile(): Profile?

    @Query("SELECT * FROM profiles WHERE id = 'profile' LIMIT 1")
    fun watchProfile(): Flow<Profile?>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertProfile(profile: Profile)

    @Query("SELECT * FROM organizations ORDER BY createdAt ASC")
    suspend fun getOrganizations(): List<Organization>

    @Query("SELECT * FROM organizations ORDER BY createdAt ASC")
    fun watchOrganizations(): Flow<List<Organization>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertOrganization(org: Organization)

    @Query("UPDATE organizations SET name = :name WHERE id = :orgId")
    suspend fun renameOrganization(orgId: String, name: String)

    @Query("DELETE FROM organizations WHERE id = :orgId")
    suspend fun deleteOrganizationRow(orgId: String)

    // -- people ---------------------------------------------------------------
    @Query("SELECT * FROM people WHERE orgId = :orgId ORDER BY name ASC")
    suspend fun getPeople(orgId: String): List<Person>

    @Query("SELECT * FROM people WHERE orgId = :orgId ORDER BY name ASC")
    fun watchPeople(orgId: String): Flow<List<Person>>

    @Query("SELECT * FROM people WHERE id = :id LIMIT 1")
    suspend fun getPerson(id: String): Person?

    @Query("SELECT * FROM people WHERE id = :id LIMIT 1")
    fun watchPerson(id: String): Flow<Person?>

    @Query("SELECT * FROM people")
    suspend fun getAllPeople(): List<Person>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertPerson(person: Person)

    @Update
    suspend fun updatePerson(person: Person)

    @Query("DELETE FROM people WHERE id = :id")
    suspend fun deletePersonRow(id: String)

    @Query("SELECT * FROM person_phones WHERE personId = :personId")
    suspend fun getPhones(personId: String): List<PersonPhone>

    @Query("SELECT * FROM person_phones WHERE personId = :personId")
    fun watchPhones(personId: String): Flow<List<PersonPhone>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertPhone(phone: PersonPhone)

    @Query("DELETE FROM person_phones WHERE id = :id")
    suspend fun deletePhone(id: String)

    @Query("SELECT * FROM person_emails WHERE personId = :personId")
    suspend fun getEmails(personId: String): List<PersonEmail>

    @Query("SELECT * FROM person_emails WHERE personId = :personId")
    fun watchEmails(personId: String): Flow<List<PersonEmail>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertEmail(email: PersonEmail)

    @Query("DELETE FROM person_emails WHERE id = :id")
    suspend fun deleteEmail(id: String)

    // -- teams ----------------------------------------------------------------
    @Query("SELECT * FROM teams WHERE orgId = :orgId ORDER BY createdAt ASC")
    suspend fun getTeams(orgId: String): List<Team>

    @Query("SELECT * FROM teams WHERE orgId = :orgId ORDER BY createdAt ASC")
    fun watchTeams(orgId: String): Flow<List<Team>>

    @Query("SELECT * FROM teams WHERE id = :id LIMIT 1")
    suspend fun getTeam(id: String): Team?

    @Query("SELECT * FROM teams WHERE id = :id LIMIT 1")
    fun watchTeam(id: String): Flow<Team?>

    @Query("SELECT * FROM teams WHERE leaderPersonId = :personId")
    suspend fun getTeamsLedBy(personId: String): List<Team>

    @Query("SELECT * FROM teams")
    suspend fun getAllTeams(): List<Team>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertTeam(team: Team)

    @Update
    suspend fun updateTeam(team: Team)

    @Query("DELETE FROM teams WHERE id = :id")
    suspend fun deleteTeamRow(id: String)

    @Query("UPDATE teams SET mainTaskId = NULL WHERE mainTaskId = :taskId")
    suspend fun clearMainTaskPointers(taskId: String)

    @Query("UPDATE teams SET mainTaskId = :taskId WHERE id = :teamId")
    suspend fun setMainTaskId(teamId: String, taskId: String?)

    @Query("UPDATE tasks SET teamId = NULL WHERE teamId = :teamId")
    suspend fun nullTeamOnTasks(teamId: String)

    // -- team members ---------------------------------------------------------
    @Query("SELECT * FROM team_members WHERE teamId = :teamId")
    suspend fun getTeamMembers(teamId: String): List<TeamMember>

    @Query("SELECT * FROM team_members WHERE teamId = :teamId")
    fun watchTeamMembers(teamId: String): Flow<List<TeamMember>>

    @Query("SELECT * FROM team_members WHERE personId = :personId")
    suspend fun getMemberships(personId: String): List<TeamMember>

    @Query("SELECT * FROM team_members WHERE teamId = :teamId AND personId = :personId LIMIT 1")
    suspend fun getMembership(teamId: String, personId: String): TeamMember?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertTeamMember(member: TeamMember)

    @Query("DELETE FROM team_members WHERE teamId = :teamId AND personId = :personId")
    suspend fun deleteTeamMember(teamId: String, personId: String)

    // -- tasks ----------------------------------------------------------------
    @Query("SELECT * FROM tasks WHERE orgId = :orgId ORDER BY isDone ASC, dueDate ASC, createdAt DESC")
    suspend fun getTasks(orgId: String): List<Task>

    @Query("SELECT * FROM tasks WHERE orgId = :orgId ORDER BY isDone ASC, dueDate ASC, createdAt DESC")
    fun watchTasks(orgId: String): Flow<List<Task>>

    @Query("SELECT * FROM tasks WHERE teamId = :teamId")
    suspend fun getTasksForTeam(teamId: String): List<Task>

    @Query("SELECT * FROM tasks WHERE teamId = :teamId")
    fun watchTasksForTeam(teamId: String): Flow<List<Task>>

    @Query("SELECT * FROM tasks WHERE id = :id LIMIT 1")
    suspend fun getTask(id: String): Task?

    @Query("SELECT * FROM tasks WHERE id = :id LIMIT 1")
    fun watchTask(id: String): Flow<Task?>

    @Query("SELECT * FROM tasks")
    suspend fun getAllTasks(): List<Task>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertTask(task: Task)

    @Update
    suspend fun updateTask(task: Task)

    @Query("DELETE FROM tasks WHERE id = :id")
    suspend fun deleteTaskRow(id: String)

    @Query("UPDATE tasks SET teamId = :teamId WHERE id = :taskId")
    suspend fun setTaskTeam(taskId: String, teamId: String?)

    @Query("UPDATE tasks SET isDone = :done, completedAt = :completedAt WHERE id = :taskId")
    suspend fun setTaskDone(taskId: String, done: Boolean, completedAt: Long?)

    // -- task assignees -------------------------------------------------------
    @Query("SELECT * FROM task_assignees WHERE taskId = :taskId")
    suspend fun getAssignees(taskId: String): List<TaskAssignee>

    @Query("SELECT * FROM task_assignees WHERE taskId = :taskId")
    fun watchAssignees(taskId: String): Flow<List<TaskAssignee>>

    @Query("SELECT * FROM task_assignees WHERE personId = :personId")
    suspend fun getAssignments(personId: String): List<TaskAssignee>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAssignee(assignee: TaskAssignee)

    @Query("DELETE FROM task_assignees WHERE taskId = :taskId AND personId = :personId")
    suspend fun deleteAssignee(taskId: String, personId: String)

    // -- sub-todos ------------------------------------------------------------
    @Query("SELECT * FROM sub_todos WHERE taskId = :taskId ORDER BY sortOrder ASC")
    suspend fun getSubTodos(taskId: String): List<SubTodo>

    @Query("SELECT * FROM sub_todos WHERE taskId = :taskId ORDER BY sortOrder ASC")
    fun watchSubTodos(taskId: String): Flow<List<SubTodo>>

    @Query("SELECT * FROM sub_todos WHERE id = :id LIMIT 1")
    suspend fun getSubTodo(id: String): SubTodo?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertSubTodo(sub: SubTodo)

    @Query("UPDATE sub_todos SET isDone = :done WHERE id = :id")
    suspend fun setSubTodoDone(id: String, done: Boolean)

    @Query("UPDATE sub_todos SET sortOrder = :sortOrder WHERE id = :id")
    suspend fun setSubTodoOrder(id: String, sortOrder: Int)

    @Query("DELETE FROM sub_todos WHERE id = :id")
    suspend fun deleteSubTodo(id: String)

    // -- whole-table clears (backup import) -----------------------------------
    @Query("DELETE FROM sub_todos")
    suspend fun clearSubTodos()

    @Query("DELETE FROM task_assignees")
    suspend fun clearAssignees()

    @Query("DELETE FROM tasks")
    suspend fun clearTasks()

    @Query("DELETE FROM team_members")
    suspend fun clearTeamMembers()

    @Query("DELETE FROM teams")
    suspend fun clearTeams()

    @Query("DELETE FROM person_phones")
    suspend fun clearPhones()

    @Query("DELETE FROM person_emails")
    suspend fun clearEmails()

    @Query("DELETE FROM people")
    suspend fun clearPeople()

    @Query("DELETE FROM organizations")
    suspend fun clearOrganizations()

    @Query("DELETE FROM profiles")
    suspend fun clearProfiles()

    @Query("SELECT * FROM person_phones")
    suspend fun getAllPhones(): List<PersonPhone>

    @Query("SELECT * FROM person_emails")
    suspend fun getAllEmails(): List<PersonEmail>

    @Query("SELECT * FROM team_members")
    suspend fun getAllTeamMembers(): List<TeamMember>

    @Query("SELECT * FROM task_assignees")
    suspend fun getAllAssignees(): List<TaskAssignee>

    @Query("SELECT * FROM sub_todos")
    suspend fun getAllSubTodos(): List<SubTodo>
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

@Database(
    entities = [
        Organization::class,
        Profile::class,
        Person::class,
        PersonPhone::class,
        PersonEmail::class,
        Team::class,
        TeamMember::class,
        Task::class,
        TaskAssignee::class,
        SubTodo::class,
    ],
    version = 1,
    exportSchema = false,
)
abstract class KeelDatabase : RoomDatabase() {
    abstract fun keelDao(): KeelDao

    companion object {
        fun open(context: Context): KeelDatabase =
            Room.databaseBuilder(context, KeelDatabase::class.java, "keel.sqlite")
                .addCallback(object : Callback() {
                    // Room enables foreign keys by default in its
                    // FrameworkSQLiteOpenHelper; no onConfigure override
                    // exists on RoomDatabase.Callback (Room 2.7).
                    override fun onCreate(db: SupportSQLiteDatabase) {
                        super.onCreate(db)
                        createIndexes(db)
                    }
                })
                .build()

        fun createIndexes(db: SupportSQLiteDatabase) {
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_tasks_org_done ON tasks (orgId, isDone)")
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_tasks_org_due ON tasks (orgId, dueDate)")
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_tasks_team ON tasks (teamId)")
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_people_org ON people (orgId)")
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_teams_org ON teams (orgId)")
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_team_members_person ON team_members (personId)")
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_task_assignees_person ON task_assignees (personId)")
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_subtodos_task ON sub_todos (taskId, sortOrder)")
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_phones_person ON person_phones (personId)")
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_emails_person ON person_emails (personId)")
        }
    }
}
