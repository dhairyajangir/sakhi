package com.example.sakhi

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channel = "com.example.sakhi/icon"
    private val sosOverlayChannel = "sakhi/sos_overlay"

    // All activity-alias names declared in AndroidManifest.xml
    private val aliases = listOf(
        "com.example.sakhi.CalculatorAlias",
        "com.example.sakhi.CalendarAlias",
        "com.example.sakhi.NotesAlias",
        "com.example.sakhi.LotusAlias",
        "com.example.sakhi.SakhiAlias",
        "com.example.sakhi.SakhiHindiAlias",
    )

    // Map from Flutter icon-name → Android alias component name
    private val iconToAlias = mapOf(
        "calculator"  to "com.example.sakhi.CalculatorAlias",
        "calendar"    to "com.example.sakhi.CalendarAlias",
        "notes"       to "com.example.sakhi.NotesAlias",
        "lotus"       to "com.example.sakhi.LotusAlias",
        "sakhi"       to "com.example.sakhi.SakhiAlias",
        "sakhi_hindi" to "com.example.sakhi.SakhiHindiAlias",
    )

    private val mainActivity = "com.example.sakhi.MainActivity"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Icon-switching channel (camouflage) ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setIcon" -> {
                        val iconName = call.argument<String?>("iconName")
                        try {
                            setIcon(iconName)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("ICON_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ── SOS Overlay channel ──
        val sosChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, sosOverlayChannel)
        sosChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        if (!Settings.canDrawOverlays(this)) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                            startActivityForResult(intent, 1234)
                            result.success(false)
                        } else {
                            result.success(true)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "hasPermission" -> {
                    val has = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        Settings.canDrawOverlays(this)
                    } else true
                    result.success(has)
                }
                "showOverlay" -> {
                    // Start the overlay service
                    val intent = Intent(this, SosOverlayService::class.java)
                    startService(intent)
                    result.success(null)
                }
                "hideOverlay" -> {
                    val intent = Intent(this, SosOverlayService::class.java)
                    stopService(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun setIcon(iconName: String?) {
        val pm = packageManager

        // Determine which component should be enabled
        val targetAlias = if (iconName != null) iconToAlias[iconName] else null

        // 1. Enable/disable the main activity
        pm.setComponentEnabledSetting(
            ComponentName(this, mainActivity),
            if (targetAlias == null)
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            else
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP,
        )

        // 2. Enable/disable each alias
        for (alias in aliases) {
            pm.setComponentEnabledSetting(
                ComponentName(this, alias),
                if (alias == targetAlias)
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                else
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
    }
}
