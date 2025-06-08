package com.example.intent_sender

import android.content.Intent
import android.os.Bundle
import java.io.File
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.intent_sender/image"

    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "sendImageBytes") {
                val bytes = call.arguments as ByteArray

                // Write bytes to a file in cacheDir
                val file = File(cacheDir, "shared_image.png")
                file.writeBytes(bytes)

                // Get content URI using FileProvider
                val uri = FileProvider.getUriForFile(
                    this,
                    "com.example.intent_sender.fileprovider",
                    file
                )

                // Create and send the intent
                val intent = Intent(Intent.ACTION_SEND).apply {
                    type = "image/png"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    `package` = "com.example.intent_receiver" // Replace with the target app's package name
                }
                startActivity(intent)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }
}
