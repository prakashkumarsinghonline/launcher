package com.example.helloworld

import android.app.Notification
import android.content.Intent
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class NotificationListener : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val packageName = sbn.packageName
        val extras = sbn.notification.extras
        val title = extras.getString(Notification.EXTRA_TITLE) ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""

        if (title.isNotEmpty() || text.isNotEmpty()) {
            val intent = Intent("com.fonehome.NOTIFICATION_EVENT")
            intent.putExtra("packageName", packageName)
            intent.putExtra("title", title)
            intent.putExtra("text", text)
            sendBroadcast(intent)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        // Handle if needed
    }
}
