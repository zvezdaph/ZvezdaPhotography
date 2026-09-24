package tv.peoplecare.remotecamera

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.Icon

object Notifications {
    const val CHANNEL_ID = "pcrc_camera"
    const val NOTIFICATION_ID = 4271

    fun createChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Camera in onda",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Stato della camera remota (pronta, in diretta, riconnessione)"
            setShowBadge(false)
            lightColor = Color.RED
        }
        manager.createNotificationChannel(channel)
    }

    fun build(context: Context, title: String, text: String, live: Boolean): Notification {
        val openIntent = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val open = PendingIntent.getActivity(
            context,
            0,
            openIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stopIntent = Intent(context, StreamingService::class.java).setAction(StreamingService.ACTION_STOP_STREAM)
        val stop = PendingIntent.getService(
            context,
            1,
            stopIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_camera)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(live)
            .setContentIntent(open)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setColor(if (live) Color.RED else Color.DKGRAY)
        if (live) {
            builder.addAction(
                Notification.Action.Builder(Icon.createWithResource(context, R.drawable.ic_stat_camera), "STOP DIRETTA", stop).build(),
            )
        }
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return builder.build()
    }
}
