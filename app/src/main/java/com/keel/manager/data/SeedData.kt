package com.keel.manager.data

import java.time.LocalDate
import java.time.ZoneId

/**
 * Sample data — Northwind Studio — behind Settings "Load sample data" ONLY.
 * The app starts empty. Mirrors the Flutter seed (lib/seed.dart) exactly:
 * 6 people, 3 teams, 6 tasks (2 done), main tasks on two teams.
 * No person is in more than 2 teams; no task has more than 3 assignees.
 */
object SeedData {
    suspend fun load(repository: KeelRepository, orgId: String) {
        val today = LocalDate.now(ZoneId.systemDefault())
        fun inDays(days: Long): Long =
            today.plusDays(days).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()

        val maya = repository.createPerson(orgId, "Maya Chen", "Creative Director", notes = "Design lead")
        val leo = repository.createPerson(orgId, "Leo Park", "Producer", notes = "Scheduling & budget")
        val sam = repository.createPerson(orgId, "Sam Ortiz", "Designer", notes = "Brand & motion")
        val priya = repository.createPerson(orgId, "Priya Nair", "Developer", notes = "Android & web")
        val dana = repository.createPerson(orgId, "Dana Reyes", "Developer", notes = "Backend & APIs")
        val tom = repository.createPerson(orgId, "Tom Weber", "Office Manager", notes = "Ops & logistics")

        val design = repository.createTeam(
            orgId, "Design", "#E5604D", maya.id, memberIds = listOf(sam.id),
        )
        val engineering = repository.createTeam(
            orgId, "Engineering", "#4F6BED", priya.id, memberIds = listOf(dana.id, maya.id),
        )
        val operations = repository.createTeam(
            orgId, "Operations", "#2E9C78", tom.id, memberIds = listOf(leo.id),
        )

        val brand = repository.createTask(
            orgId,
            title = "Brand refresh",
            notes = "New palette, type and logo system.",
            dueDate = inDays(3),
            priority = "high",
            teamId = design.id,
            assigneeIds = listOf(maya.id, sam.id),
            subTodoTitles = listOf("Moodboard", "Palette", "Type scale"),
        )
        repository.setMainTask(design.id, brand.id)

        val sprint = repository.createTask(
            orgId,
            title = "Sprint 12 planning",
            notes = "Scope the next two weeks.",
            dueDate = inDays(1),
            priority = "medium",
            teamId = engineering.id,
            assigneeIds = listOf(priya.id, dana.id),
            subTodoTitles = listOf("Backlog grooming", "Capacity check"),
        )
        repository.setMainTask(engineering.id, sprint.id)

        repository.createTask(
            orgId,
            title = "Fix login crash",
            notes = "Null session on cold start.",
            dueDate = inDays(-1),
            priority = "high",
            teamId = engineering.id,
            assigneeIds = listOf(dana.id),
        )
        repository.createTask(
            orgId,
            title = "Client call notes",
            notes = "Northwind kickoff — decisions and open questions.",
            dueDate = inDays(5),
            priority = "low",
            assigneeIds = listOf(leo.id),
        )
        repository.createTask(
            orgId,
            title = "Order studio supplies",
            notes = "Paper, inks and cable ties.",
            dueDate = null,
            priority = "low",
            teamId = operations.id,
            assigneeIds = listOf(tom.id),
        )
        val doneTask = repository.createTask(
            orgId,
            title = "Set up project folders",
            notes = "Shared drive structure for Northwind.",
            dueDate = inDays(-3),
            priority = "none",
            teamId = operations.id,
            assigneeIds = listOf(tom.id, leo.id),
            subTodoTitles = listOf("Drive folders", "Naming guide"),
        )
        repository.setTaskDone(doneTask.id, true)

        val done2 = repository.createTask(
            orgId,
            title = "Review portfolio site",
            notes = "Copy pass and broken links.",
            dueDate = inDays(-2),
            priority = "medium",
            assigneeIds = listOf(maya.id),
        )
        repository.setTaskDone(done2.id, true)
    }
}
