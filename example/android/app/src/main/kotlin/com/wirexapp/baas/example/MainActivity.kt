package com.wirexapp.baas.example

import android.content.Intent
import android.os.Build
import android.os.Process
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The Config tab's diagnostic log: the system share sheet, this process's own logcat (where
        // the native SDK writes its diagnostics) and the app's identity for the log header.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wirex.example/diagnostics")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "share" -> {
                        val text = call.argument<String>("text") ?: ""
                        val send = Intent(Intent.ACTION_SEND)
                            .setType("text/plain")
                            .putExtra(Intent.EXTRA_SUBJECT, "Wirex Mobile SDK example — diagnostic log")
                            .putExtra(Intent.EXTRA_TEXT, text)
                        startActivity(Intent.createChooser(send, "Share diagnostic log"))
                        result.success(null)
                    }
                    "nativeLog" -> result.success(ownLogcat())
                    "appInfo" -> {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        @Suppress("DEPRECATION")
                        val build = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else info.versionCode.toLong()
                        result.success(
                            mapOf(
                                "appId" to packageName,
                                "version" to (info.versionName ?: "?"),
                                "build" to build.toString(),
                                "model" to "${Build.MANUFACTURER} ${Build.MODEL}",
                                "os" to "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
                            ),
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** This process's own logcat lines (an app may read its own without `READ_LOGS`), newest last. */
    private fun ownLogcat(): String = try {
        val process = ProcessBuilder("logcat", "-d", "-v", "time", "--pid=${Process.myPid()}", "-t", "4000")
            .redirectErrorStream(true)
            .start()
        val lines = process.inputStream.bufferedReader().use { it.readLines() }
        // The SDK's own tags (`Wirex…`), plus every error and crash; the system's chatter is left out.
        val kept = lines.filter { line ->
            val level = Regex("""\s([VDIWEF])/""").find(line)?.groupValues?.get(1)
            line.contains("/Wirex", ignoreCase = true) || level == "E" || level == "F"
        }
        "(${kept.size} SDK / error lines of ${lines.size})\n" + kept.joinToString("\n")
    } catch (e: Exception) {
        "logcat unavailable: ${e.javaClass.simpleName}: ${e.message}"
    }
}
