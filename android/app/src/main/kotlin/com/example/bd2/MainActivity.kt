package com.example.bd2

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bd2/announcements").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(NewsNotifier.status(this))
                    "requestPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            if (permissionResult != null) result.error("BUSY", "Permission request already open", null)
                            else { permissionResult = result; requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 18401) }
                        } else result.success(NewsNotifier.allowed(this))
                    }
                    "setEnabled" -> { NewsNotifier.setEnabled(this, call.argument<Boolean>("enabled") == true); result.success(null) }
                    "setCategory" -> { NewsNotifier.category(this, call.argument<String>("category") ?: "", call.argument<Boolean>("enabled") == true); result.success(null) }
                    "observe" -> {
                        val items = call.argument<List<Map<String, Any?>>>("items") ?: emptyList()
                        require(items.size <= 100)
                        val locale = items.firstOrNull()?.get("locale")?.toString() ?: "zh-cn"
                        NewsNotifier.observe(this, JSONArray(items), locale)
                        result.success(null)
                    }
                    "schedule" -> {
                        NewsNotifier.scheduleReminder(this, JSONObject(call.arguments as Map<*, *>)); result.success(null)
                    }
                    "cancelReminder" -> { NewsNotifier.cancelReminder(this, call.argument<String>("id") ?: ""); result.success(null) }
                    "test" -> { NewsNotifier.test(this); result.success(null) }
                    "settings" -> {
                        val settings = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        if (Build.VERSION.SDK_INT >= 26) startActivity(settings)
                        else startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.parse("package:$packageName")))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) { result.error("NEWS_ERROR", error.message, null) }
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 18401) { permissionResult?.success(NewsNotifier.allowed(this)); permissionResult = null }
    }
}