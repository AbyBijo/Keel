package com.keel.manager.data

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.keel.manager.MainActivity
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import kotlinx.coroutines.launch

// ---------------------------------------------------------------------------
// Daily digest — platform APIs only (NotificationManager + AlarmManager).
// No notifications plugin: the Flutter build failed three times on its
// notifications plugin (desugaring, then java.time on Java 11, then a
// floating 19.5.0). This code uses only APIs present since API 26 and
// java.time, which is native from API 26 — no desugaring needed.
// ---------------------------------------------------------------------------

const val DIGEST_CHANNEL_ID = "keel_daily_digest"
private const val DIGEST_REQUEST_CODE = 1001
private const val DIGEST_NOTIFICATION_ID = 2001

object DigestScheduler {
    fun schedule(context: Context, hour: Int, minute: Int) {
        cancel(context)
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, DigestReceiver::class.java)
        val pending = PendingIntent.getBroadcast(
            context,
            DIGEST_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val now = LocalDateTime.now()
        var trigger = now.withHour(hour).withMinute(minute).withSecond(0).withNano(0)
        if (!trigger.isAfter(now)) trigger = trigger.plusDays(1)
        val triggerMillis = trigger.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
            // Exact alarms not granted: fall back to an inexact daily alarm
            // rather than crashing or silently doing nothing.
            alarmManager.setInexactRepeating(
                AlarmManager.RTC_WAKEUP,
                triggerMillis,
                AlarmManager.INTERVAL_DAY,
                pending,
            )
        } else {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerMillis, pending)
        }
    }

    fun cancel(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, DigestReceiver::class.java)
        val pending = PendingIntent.getBroadcast(
            context,
            DIGEST_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        alarmManager.cancel(pending)
        pending.cancel()
    }
}

/** Fires at the scheduled digest time, shows one summary notification,
 * then re-schedules itself for tomorrow. */
class DigestReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val container = (context.applicationContext as? com.keel.manager.KeelApp)?.container
            ?: return
        val repo = container.repository
        val settings = container.settingsStore
        // Re-schedule first so the digest keeps coming even if this run fails.
        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch {
            try {
                val s = settings.current()
                if (!s.remindersOn) return@launch
                DigestScheduler.schedule(context, s.digestHour, s.digestMinute)
                val orgId = s.activeOrgId ?: repo.getOrganizations().firstOrNull()?.id ?: return@launch
                val stats = repo.homeStats(orgId)
                val open = stats.total - stats.done
                if (open <= 0 && stats.overdue == 0) return@launch
                val body = buildString {
                    if (stats.overdue > 0) append("$open open · ${stats.overdue} overdue")
                    else append("$open open tasks")
                    if (stats.dueSoon > 0) append(" · ${stats.dueSoon} due soon")
                }
                showDigest(context, body)
            } catch (_: Exception) {
                // A digest must never crash the app.
            }
        }
    }

    private fun showDigest(context: Context, body: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                DIGEST_CHANNEL_ID,
                "Daily digest",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply { description = "A daily summary of open and overdue tasks." }
            manager.createNotificationChannel(channel)
        }
        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pending = PendingIntent.getActivity(
            context, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, DIGEST_CHANNEL_ID)
            .setSmallIcon(com.keel.manager.R.drawable.ic_anchor)
            .setContentTitle("Your day in Keel")
            .setContentText(body)
            .setContentIntent(pending)
            .setAutoCancel(true)
            .build()
        manager.notify(DIGEST_NOTIFICATION_ID, notification)
    }
}

/** Re-schedules the digest after a reboot (alarms do not survive one). */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val container = (context.applicationContext as? com.keel.manager.KeelApp)?.container
            ?: return
        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch {
            try {
                val s = container.settingsStore.current()
                if (s.remindersOn) {
                    DigestScheduler.schedule(context, s.digestHour, s.digestMinute)
                }
            } catch (_: Exception) {
                // A missed re-schedule must never crash the boot sequence.
            }
        }
    }
}

/** True when the digest time is today and has not passed yet. */
fun nextDigestToday(hour: Int, minute: Int): LocalDateTime {
    val now = LocalDateTime.now()
    val t = now.withHour(hour).withMinute(minute).withSecond(0).withNano(0)
    return if (t.isAfter(now)) t else t.plusDays(1)
}

@Suppress("unused")
fun todayDate(): LocalDate = LocalDate.now(ZoneId.systemDefault())
