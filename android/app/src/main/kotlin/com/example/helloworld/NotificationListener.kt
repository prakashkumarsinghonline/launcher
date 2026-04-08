package com.example.helloworld

import android.app.Notification
import android.content.Intent
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class NotificationListener : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val packageName = sbn.packageName
        val extras = sbn.notification.extras
        val title = extras.getString(Notification.EXTRA_TITLE) ?: extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        var text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        
        // Handle WhatsApp and other messaging apps
        if (text.isEmpty()) {
            val textLines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
            if (textLines != null && textLines.isNotEmpty()) {
                text = textLines.last().toString()
            }
        }

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
