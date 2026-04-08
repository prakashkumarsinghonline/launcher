package com.example.helloworld

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.provider.Settings
import android.media.MediaRecorder
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.fonehome.launcher/apps"
    private val EVENT_CHANNEL = "com.fonehome.launcher/notifications"
    private var notificationReceiver: BroadcastReceiver? = null
    
    private var mediaRecorder: MediaRecorder? = null
    private var isRecording = false
    private var currentRecordingPath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledApps" -> {
                    val apps = getInstalledApps()
                    result.success(apps)
                }
                "launchApp" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        val success = launchApp(packageName)
                        if (success) {
                            result.success(true)
                        } else {
                            result.error("UNAVAILABLE", "App not available or could not be launched.", null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Package name is null", null)
                    }
                }
                "requestNotificationAccess" -> {
                    val intent = Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
                    startActivity(intent)
                    result.success(true)
                }
                "isNotificationAccessGranted" -> {
                    val enabledListeners = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
                    val isGranted = enabledListeners?.contains(packageName) == true
                    result.success(isGranted)
                }
                "disableApp" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        try {
                            packageManager.setApplicationEnabledSetting(
                                packageName,
                                PackageManager.COMPONENT_ENABLED_STATE_DISABLED_USER,
                                0
                            )
                            result.success(true)
                        } catch (e: SecurityException) {
                            result.error("SECURITY_EXCEPTION", "Cannot disable app without root or device admin privileges.", e.message)
                        } catch (e: Exception) {
                            result.error("ERROR", "Failed to disable app.", e.message)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Package name is null", null)
                    }
                }
                "startRecording" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        val success = startRecording(path)
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGUMENT", "Path is null", null)
                    }
                }
                "stopRecording" -> {
                    val path = stopRecording()
                    result.success(path)
                }
                "isRecording" -> {
                    result.success(isRecording)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    notificationReceiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context?, intent: Intent?) {
                            if (intent?.action == "com.fonehome.NOTIFICATION_EVENT") {
                                val packageName = intent.getStringExtra("packageName")
                                val title = intent.getStringExtra("title")
                                val text = intent.getStringExtra("text")
                                
                                val notificationData = mapOf(
                                    "packageName" to packageName,
                                    "title" to title,
                                    "text" to text
                                )
                                events?.success(notificationData)
                            }
                        }
                    }
                    val filter = IntentFilter("com.fonehome.NOTIFICATION_EVENT")
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        registerReceiver(notificationReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
                    } else {
                        registerReceiver(notificationReceiver, filter)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    notificationReceiver?.let {
                        unregisterReceiver(it)
                        notificationReceiver = null
                    }
                }
            }
        )
    }

    private fun getBitmapFromDrawable(drawable: Drawable): Bitmap {
        if (drawable is BitmapDrawable && drawable.bitmap != null) {
            return drawable.bitmap
        }
        val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 1
        val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 1
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return bitmap
    }

    private fun getInstalledApps(): List<Map<String, Any>> {
        val apps = mutableListOf<Map<String, Any>>()
        val intent = Intent(Intent.ACTION_MAIN, null)
        intent.addCategory(Intent.CATEGORY_LAUNCHER)
        
        val pm: PackageManager = packageManager
        val list: List<ResolveInfo> = pm.queryIntentActivities(intent, 0)
        
        for (resolveInfo in list) {
            val packageName = resolveInfo.activityInfo.packageName
            // don't include ourselves
            if (packageName == this.packageName) {
                continue
            }
            val appName = resolveInfo.loadLabel(pm).toString()
            
            val iconDrawable = resolveInfo.loadIcon(pm)
            val bitmap = getBitmapFromDrawable(iconDrawable)
            val scaledBitmap = Bitmap.createScaledBitmap(bitmap, 96, 96, true)
            val stream = ByteArrayOutputStream()
            scaledBitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            val iconByteArray = stream.toByteArray()
            
            val appInfo = mapOf(
                "packageName" to packageName,
                "appName" to appName,
                "icon" to iconByteArray
            )
            apps.add(appInfo)
        }
        
        return apps.sortedBy { (it["appName"] as String).lowercase() }
    }

    private fun launchApp(packageName: String): Boolean {
        return try {
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(launchIntent)
                true
            } else {
                false
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun startRecording(path: String): Boolean {
        if (isRecording) return false
        
        return try {
            mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(this)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }
            
            mediaRecorder?.apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setOutputFile(path)
                prepare()
                start()
            }
            isRecording = true
            currentRecordingPath = path
            true
        } catch (e: Exception) {
            e.printStackTrace()
            mediaRecorder?.release()
            mediaRecorder = null
            isRecording = false
            currentRecordingPath = null
            false
        }
    }

    private fun stopRecording(): String? {
        if (!isRecording) return null
        
        return try {
            mediaRecorder?.apply {
                stop()
                release()
            }
            mediaRecorder = null
            isRecording = false
            val path = currentRecordingPath
            currentRecordingPath = null
            path
        } catch (e: Exception) {
            e.printStackTrace()
            mediaRecorder?.release()
            mediaRecorder = null
            isRecording = false
            currentRecordingPath = null
            null
        }
    }
}
