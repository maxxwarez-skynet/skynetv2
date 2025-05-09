package com.example.skynet

import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.skynet/wifi"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "openWifiSettings") {
                try {
                    // Try to open the WiFi settings panel first (Android 10+)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val panelIntent = Intent(Settings.Panel.ACTION_WIFI)
                        startActivity(panelIntent)
                        result.success(true)
                    } else {
                        // Fallback for older Android versions
                        val intent = Intent(Settings.ACTION_WIFI_SETTINGS)
                        startActivity(intent)
                        result.success(true)
                    }
                } catch (e: Exception) {
                    result.error("UNAVAILABLE", "WiFi settings not available: ${e.message}", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
