package com.example.zen_launcher // <-- MAKE SURE THIS MATCHES YOUR EXISTING PACKAGE NAME

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity: FlutterActivity() {
    private val EVENT_CHANNEL = "com.zen.launcher/app_change_events"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                private var receiver: BroadcastReceiver? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    // 1. Define the receiver
                    receiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context?, intent: Intent?) {
                            // Send the event type (e.g., "android.intent.action.PACKAGE_ADDED") to Flutter
                            events?.success(intent?.action)
                        }
                    }

                    // 2. Define what we are listening for
                    val filter = IntentFilter().apply {
                        addAction(Intent.ACTION_PACKAGE_ADDED)
                        addAction(Intent.ACTION_PACKAGE_REMOVED)
                        addAction(Intent.ACTION_PACKAGE_FULLY_REMOVED)
                        addDataScheme("package") // Essential: Listen for package changes
                    }

                    // 3. Register it
                    context.registerReceiver(receiver, filter)
                }

                override fun onCancel(arguments: Any?) {
                    // Clean up to prevent memory leaks
                    if (receiver != null) {
                        context.unregisterReceiver(receiver)
                        receiver = null
                    }
                }
            }
        )
    }
}