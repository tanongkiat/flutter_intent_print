package com.example.intent_receiver

import android.content.Intent
import android.os.Bundle
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "intent_receiver/imagebytes"
    private var latestIntent: Intent? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        latestIntent = intent
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        latestIntent = intent
        setIntent(intent)
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getImageBytes") {
                val intent = latestIntent
                if (intent != null && (
                        intent.action == "intent_receiver.imagebytes" ||
                        intent.action == Intent.ACTION_SEND
                    )) {
                    val uri = intent.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM)
                    if (uri != null) {
                        try {
                            val inputStream: InputStream? = contentResolver.openInputStream(uri)
                            val bytes = inputStream?.readBytes()
                            inputStream?.close()
                            if (bytes != null) {
                                result.success(bytes)
                                return@setMethodCallHandler
                            }
                        } catch (e: Exception) {
                            result.error("UNAVAILABLE", "Failed to read image bytes: ${e.message}", null)
                            return@setMethodCallHandler
                        }
                    }
                }
                result.success(null)
            }
        }
    }
}
