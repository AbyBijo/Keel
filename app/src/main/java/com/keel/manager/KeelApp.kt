package com.keel.manager

import android.app.Application
import com.keel.manager.data.KeelDatabase
import com.keel.manager.data.KeelRepository
import com.keel.manager.data.SettingsStore

/** Manual DI container — no DI framework, nothing to misconfigure. */
class AppContainer(application: Application) {
    val database: KeelDatabase = KeelDatabase.open(application)
    val repository: KeelRepository = KeelRepository(database)
    val settingsStore: SettingsStore = SettingsStore(application)
}

class KeelApp : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }
}
