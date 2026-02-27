package com.example.sakhi

import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView

/**
 * Android Service that creates a floating SOS button overlay using
 * SYSTEM_ALERT_WINDOW permission. The button stays on top of all apps
 * (including Google Maps during navigation) and, when tapped, sends
 * the user back to the Sakhi app to trigger the SOS/Broadcast flow.
 */
class SosOverlayService : Service() {

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null

    override fun onBind(intent: Intent?): IBinder? = null

    /** Convert density-independent pixels to actual pixels. */
    private fun dpToPx(dp: Int): Int {
        val density = resources.displayMetrics.density
        return (dp * density + 0.5f).toInt()
    }

    override fun onCreate() {
        super.onCreate()
        // Guard: verify overlay permission before showing the button
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            Log.e("SosOverlayService", "SYSTEM_ALERT_WINDOW permission not granted — stopping self")
            stopSelf()
            return
        }
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        showOverlayButton()
    }

    override fun onDestroy() {
        super.onDestroy()
        removeOverlay()
    }

    private fun showOverlayButton() {
        if (overlayView != null) return

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            dpToPx(160), // width
            dpToPx(160), // height
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.END
            x = dpToPx(40)
            y = dpToPx(200)
        }

        // Build the overlay view programmatically
        val frame = FrameLayout(this).apply {
            setBackgroundColor(Color.TRANSPARENT)
        }

        // Circular red SOS button
        val buttonSize = dpToPx(140)
        val button = FrameLayout(this).apply {
            val lp = FrameLayout.LayoutParams(buttonSize, buttonSize)
            lp.gravity = Gravity.CENTER
            layoutParams = lp

            background = android.graphics.drawable.GradientDrawable().apply {
                shape = android.graphics.drawable.GradientDrawable.OVAL
                setColor(Color.parseColor("#F44336"))
                setStroke(dpToPx(4), Color.parseColor("#D32F2F"))
            }
            elevation = 12f

            // Accessibility: label for screen readers
            contentDescription = "SOS button, double tap to call for help"
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
        }

        val label = TextView(this).apply {
            text = "SOS"
            setTextColor(Color.WHITE)
            textSize = 18f
            gravity = Gravity.CENTER
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            val lp = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            layoutParams = lp
        }
        button.addView(label)
        frame.addView(button)

        // Make it draggable + clickable
        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        var moved = false

        frame.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (initialTouchX - event.rawX).toInt()
                    val dy = (initialTouchY - event.rawY).toInt()
                    if (Math.abs(dx) > 10 || Math.abs(dy) > 10) moved = true
                    params.x = initialX + dx
                    params.y = initialY + dy
                    windowManager?.updateViewLayout(frame, params)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) {
                        // Tap → open Sakhi and trigger SOS
                        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                        launchIntent?.apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                            putExtra("trigger_sos", true)
                        }
                        if (launchIntent != null) startActivity(launchIntent)
                    }
                    true
                }
                else -> false
            }
        }

        overlayView = frame
        windowManager?.addView(frame, params)
    }

    private fun removeOverlay() {
        overlayView?.let {
            windowManager?.removeView(it)
            overlayView = null
        }
    }
}
