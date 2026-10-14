package com.banknote.banknote_identifier

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Passes launcher shortcuts and Google Assistant intents ("scan money",
 * "around me", "voice command") to Dart over the `notelens/system` channel,
 * and opens the text-to-speech settings so users can download voices.
 */
class MainActivity : FlutterActivity() {
    private var pendingAction: String? = null
    private var channel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingAction = actionFrom(intent)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "notelens/system").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeLaunchAction" -> {
                        result.success(pendingAction)
                        pendingAction = null
                    }
                    "openTtsSettings" -> {
                        try {
                            startActivity(Intent("com.android.settings.TTS_SETTINGS").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        } catch (e: Exception) {
                            try {
                                startActivity(Intent(android.speech.tts.TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA))
                            } catch (_: Exception) {
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val action = actionFrom(intent) ?: return
        val ch = channel
        if (ch != null) ch.invokeMethod("launchAction", action) else pendingAction = action
    }

    /** "action" extra from a shortcut, or the Assistant's OPEN_APP_FEATURE "feature". */
    private fun actionFrom(intent: Intent?): String? {
        if (intent == null) return null
        intent.getStringExtra("action")?.let { return it }
        val feature = intent.getStringExtra("feature")?.lowercase() ?: intent.data?.getQueryParameter("feature")?.lowercase()
            ?: return null
        return when {
            listOf("money", "scan", "pesa", "note").any { feature.contains(it) } -> "scan_money"
            listOf("around", "object", "surround", "mbele").any { feature.contains(it) } -> "around_me"
            listOf("voice", "command", "sauti").any { feature.contains(it) } -> "voice_command"
            else -> null
        }
    }
}
