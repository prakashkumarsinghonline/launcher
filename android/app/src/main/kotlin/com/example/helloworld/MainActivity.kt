package com.example.helloworld

import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.fonehome.launcher/apps"

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
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getInstalledApps(): List<Map<String, String>> {
        val apps = mutableListOf<Map<String, String>>()
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
            
            val appInfo = mapOf(
                "packageName" to packageName,
                "appName" to appName
            )
            apps.add(appInfo)
        }
        
        return apps.sortedBy { it["appName"]?.lowercase() }
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
}
