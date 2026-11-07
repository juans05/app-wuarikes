package com.wuarikes.wuarikes_app

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Opens the battery-optimization list. Unlike ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
        // this needs no Play-restricted permission.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wuarikes/battery")
            .setMethodCallHandler { call, result ->
                if (call.method == "openSettings") {
                    try {
                        startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                    } catch (e: Exception) {
                        startActivity(Intent(Settings.ACTION_SETTINGS))
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
