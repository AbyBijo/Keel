package com.keel.manager.data

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

// ---------------------------------------------------------------------------
// Entities — exactly the data model in section 4 of the master prompt.
// Dates are epoch millis. dueDate is always stored at start-of-day.
// ---------------------------------------------------------------------------

@Entity(tableName = "organizations")
data class Organization(
    @PrimaryKey val id: String,
    val name: String,
    /** Studio, Company, Club, Family, Other */
    val kind: String,
    val createdAt: Long,
)

@Entity(tableName = "profiles")
data class Profile(
    /** Single row, id = "profile". */
    @PrimaryKey val id: String = "profile",
    val name: String,
    /** Single, global role. */
    val role: String,
)

@Entity(
    tableName = "people",
    foreignKeys = [
        ForeignKey(
            entity = Organization::class,
            parentColumns = ["id"],
            childColumns = ["orgId"],
        ),
    ],
    indices = [Index("orgId")],
)
data class Person(
    @PrimaryKey val id: String,
    val orgId: String,
    val name: String,
    val roleTitle: String,
    /** App-private file path only; the photo itself lives in app storage. */
    val photoPath: String?,
    val notes: String,
    val createdAt: Long,
)

@Entity(
    tableName = "person_phones",
    foreignKeys = [
        ForeignKey(
            entity = Person::class,
            parentColumns = ["id"],
            childColumns = ["personId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index("personId")],
)
data class PersonPhone(
    @PrimaryKey val id: String,
    val personId: String,
    /** mobile, work, home, other */
    val label: String,
    val number: String,
)

@Entity(
    tableName = "person_emails",
    foreignKeys = [
        ForeignKey(
            entity = Person::class,
            parentColumns = ["id"],
            childColumns = ["personId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index("personId")],
)
data class PersonEmail(
    @PrimaryKey val id: String,
    val personId: String,
    val label: String,
    val address: String,
)

@Entity(
    tableName = "teams",
    foreignKeys = [
        ForeignKey(
            entity = Organization::class,
            parentColumns = ["id"],
            childColumns = ["orgId"],
        ),
        ForeignKey(
            entity = Person::class,
            parentColumns = ["id"],
            childColumns = ["leaderPersonId"],
        ),
    ],
    indices = [Index("orgId"), Index("leaderPersonId")],
)
data class Team(
    @PrimaryKey val id: String,
    val orgId: String,
    val name: String,
    val colorHex: String,
    /** Required; must be a member (enforced in the repository, rule 4). */
    val leaderPersonId: String,
    /**
     * Nullable. Deliberately NO foreign key: Teams.mainTaskId and
     * Tasks.teamId are circular, so — exactly like the Flutter build —
     * this side is a plain column and the repository clears it
     * explicitly when a task is deleted (see Repository._deleteTaskRows).
     */
    val mainTaskId: String?,
    val createdAt: Long,
)

@Entity(
    tableName = "team_members",
    primaryKeys = ["teamId", "personId"],
    foreignKeys = [
        ForeignKey(
            entity = Team::class,
            parentColumns = ["id"],
            childColumns = ["teamId"],
            onDelete = ForeignKey.CASCADE,
        ),
        ForeignKey(
            entity = Person::class,
            parentColumns = ["id"],
            childColumns = ["personId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index("personId")],
)
data class TeamMember(
    val teamId: String,
    val personId: String,
)

@Entity(
    tableName = "tasks",
    foreignKeys = [
        ForeignKey(
            entity = Organization::class,
            parentColumns = ["id"],
            childColumns = ["orgId"],
        ),
        ForeignKey(
            entity = Team::class,
            parentColumns = ["id"],
            childColumns = ["teamId"],
            onDelete = ForeignKey.SET_NULL,
        ),
    ],
    indices = [Index("orgId"), Index("teamId"), Index("dueDate")],
)
data class Task(
    @PrimaryKey val id: String,
    val orgId: String,
    val title: String,
    val notes: String,
    /** Start-of-day epoch millis, or null. */
    val dueDate: Long?,
    /** none, low, medium, high */
    val priority: String,
    /** Nullable. Deleting a team sets this to NULL (tasks survive). */
    val teamId: String?,
    val isDone: Boolean,
    val completedAt: Long?,
    val createdAt: Long,
)

/** The ONLY assignment table (logic rule 1). */
@Entity(
    tableName = "task_assignees",
    primaryKeys = ["taskId", "personId"],
    foreignKeys = [
        ForeignKey(
            entity = Task::class,
            parentColumns = ["id"],
            childColumns = ["taskId"],
            onDelete = ForeignKey.CASCADE,
        ),
        ForeignKey(
            entity = Person::class,
            parentColumns = ["id"],
            childColumns = ["personId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index("personId")],
)
data class TaskAssignee(
    val taskId: String,
    val personId: String,
)

@Entity(
    tableName = "sub_todos",
    foreignKeys = [
        ForeignKey(
            entity = Task::class,
            parentColumns = ["id"],
            childColumns = ["taskId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index("taskId")],
)
data class SubTodo(
    @PrimaryKey val id: String,
    val taskId: String,
    val title: String,
    val isDone: Boolean,
    val sortOrder: Int,
)

// ---------------------------------------------------------------------------
// Date helpers (rule 8)
// ---------------------------------------------------------------------------

/** Start of the given day, in the device timezone, as epoch millis. */
fun startOfDayMillis(millis: Long): Long {
    val date = Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()).toLocalDate()
    return date.atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
}

/** Start of today, as epoch millis. */
fun todayStartMillis(nowMillis: Long = System.currentTimeMillis()): Long =
    startOfDayMillis(nowMillis)

/** Start-of-day LocalDate for a stored due date. */
fun LocalDate.toStartMillis(): Long =
    atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()

/** Overdue = not done and dueDate before today. */
fun isOverdue(task: Task, nowMillis: Long = System.currentTimeMillis()): Boolean {
    if (task.isDone || task.dueDate == null) return false
    return startOfDayMillis(task.dueDate) < todayStartMillis(nowMillis)
}

/** Due soon = not done and due within 2 days (today included). */
fun isDueSoon(task: Task, nowMillis: Long = System.currentTimeMillis()): Boolean {
    if (task.isDone || task.dueDate == null) return false
    val today = todayStartMillis(nowMillis)
    val diffDays = (startOfDayMillis(task.dueDate) - today) / 86_400_000L
    return diffDays in 0..2
}

/** Greeting by time of day, as on Home. */
fun greetingFor(hour: Int): String = when {
    hour < 12 -> "Good morning"
    hour < 17 -> "Good afternoon"
    else -> "Good evening"
}

fun initialsOf(name: String): String {
    val parts = name.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
    if (parts.isEmpty()) return "?"
    if (parts.size == 1) return parts.first().first().uppercase()
    return "${parts.first().first()}${parts.last().first()}".uppercase()
}
