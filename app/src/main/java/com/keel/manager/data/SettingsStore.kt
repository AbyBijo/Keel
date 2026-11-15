package com.keel.manager.data

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.dataStore by preferencesDataStore(name = "keel_settings")

enum class ThemeMode { SYSTEM, LIGHT, DARK }

data class AppSettings(
    val onboardingDone: Boolean = false,
    val activeOrgId: String? = null,
    val themeMode: ThemeMode = ThemeMode.SYSTEM,
    val textScale: Float = 1.0f,
    val reduceMotion: Boolean = false,
    val accentHex: String? = null,
    val remindersOn: Boolean = false,
    val digestHour: Int = 8,
    val digestMinute: Int = 0,
    val lastBackupAt: Long? = null,
    /** Set once after first Home visit — used for the first-run tip. */
    val homeSeenOnce: Boolean = false,
)

/** Keys mirror the Flutter provider defaults (lib/providers.dart). */
class SettingsStore(private val context: Context) {
    private object Keys {
        val ONBOARDING_DONE = booleanPreferencesKey("onboarding_done")
        val ACTIVE_ORG_ID = stringPreferencesKey("active_org_id")
        val THEME_MODE = stringPreferencesKey("theme_mode")
        val TEXT_SCALE = floatPreferencesKey("text_scale")
        val REDUCE_MOTION = booleanPreferencesKey("reduce_motion")
        val ACCENT_HEX = stringPreferencesKey("accent_hex")
        val REMINDERS_ON = booleanPreferencesKey("reminders_on")
        val DIGEST_HOUR = floatPreferencesKey("digest_hour")
        val DIGEST_MINUTE = floatPreferencesKey("digest_minute")
        val LAST_BACKUP_AT = floatPreferencesKey("last_backup_at")
        val HOME_SEEN_ONCE = booleanPreferencesKey("home_seen_once")
    }

    val settings: Flow<AppSettings> = context.dataStore.data.map { p ->
        AppSettings(
            onboardingDone = p[Keys.ONBOARDING_DONE] ?: false,
            activeOrgId = p[Keys.ACTIVE_ORG_ID],
            themeMode = when (p[Keys.THEME_MODE] ?: "system") {
                "light" -> ThemeMode.LIGHT
                "dark" -> ThemeMode.DARK
                else -> ThemeMode.SYSTEM
            },
            textScale = (p[Keys.TEXT_SCALE] ?: 1.0f).coerceIn(0.8f, 1.5f),
            reduceMotion = p[Keys.REDUCE_MOTION] ?: false,
            accentHex = p[Keys.ACCENT_HEX],
            remindersOn = p[Keys.REMINDERS_ON] ?: false,
            digestHour = (p[Keys.DIGEST_HOUR] ?: 8f).toInt(),
            digestMinute = (p[Keys.DIGEST_MINUTE] ?: 0f).toInt(),
            lastBackupAt = p[Keys.LAST_BACKUP_AT]?.toLong(),
            homeSeenOnce = p[Keys.HOME_SEEN_ONCE] ?: false,
        )
    }

    suspend fun current(): AppSettings = settings.first()

    suspend fun setOnboardingDone(done: Boolean = true) {
        context.dataStore.edit { it[Keys.ONBOARDING_DONE] = done }
    }

    suspend fun setActiveOrgId(id: String?) {
        context.dataStore.edit {
            if (id == null) it.remove(Keys.ACTIVE_ORG_ID) else it[Keys.ACTIVE_ORG_ID] = id
        }
    }

    suspend fun setThemeMode(mode: ThemeMode) {
        context.dataStore.edit {
            it[Keys.THEME_MODE] = when (mode) {
                ThemeMode.SYSTEM -> "system"
                ThemeMode.LIGHT -> "light"
                ThemeMode.DARK -> "dark"
            }
        }
    }

    suspend fun setTextScale(scale: Float) {
        context.dataStore.edit { it[Keys.TEXT_SCALE] = scale.coerceIn(0.8f, 1.5f) }
    }

    suspend fun setReduceMotion(value: Boolean) {
        context.dataStore.edit { it[Keys.REDUCE_MOTION] = value }
    }

    suspend fun setAccentHex(hex: String?) {
        context.dataStore.edit {
            if (hex == null) it.remove(Keys.ACCENT_HEX) else it[Keys.ACCENT_HEX] = hex
        }
    }

    suspend fun setRemindersOn(value: Boolean) {
        context.dataStore.edit { it[Keys.REMINDERS_ON] = value }
    }

    suspend fun setDigestTime(hour: Int, minute: Int) {
        context.dataStore.edit {
            it[Keys.DIGEST_HOUR] = hour.toFloat()
            it[Keys.DIGEST_MINUTE] = minute.toFloat()
        }
    }

    suspend fun setLastBackupAt(millis: Long) {
        context.dataStore.edit { it[Keys.LAST_BACKUP_AT] = millis.toFloat() }
    }

    suspend fun setHomeSeenOnce() {
        context.dataStore.edit { it[Keys.HOME_SEEN_ONCE] = true }
    }

    /** Reset every setting (used by "Reset all data" only after confirmation). */
    suspend fun clearAll() {
        context.dataStore.edit { it.clear() }
    }
}
