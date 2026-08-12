package com.example.on_server

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result

/// Bridges the Setup Wizard (lib/core/termux_bridge.dart) to Termux's
/// RUN_COMMAND API. See server/scripts and the Setup Wizard screen for how
/// these are used together.
class MainActivity : FlutterActivity() {
    private val channelName = "on_server/termux"
    private val termuxPackage = "com.termux"

    // com.termux.permission.RUN_COMMAND is declared by Termux itself with
    // protectionLevel="dangerous", so — unlike most inter-app intents — it
    // requires an explicit runtime grant from the user via
    // ActivityCompat.requestPermissions, same as camera/location permissions.
    private val runCommandPermission = "com.termux.permission.RUN_COMMAND"
    private val runCommandRequestCode = 4201

    private var pendingPermissionResult: Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "isTermuxInstalled" -> result.success(isTermuxInstalled())
                "openTermux" -> result.success(openTermux())
                "openTermuxInstallPage" -> {
                    openTermuxInstallPage()
                    result.success(null)
                }
                "hasRunCommandPermission" -> result.success(hasRunCommandPermission())
                "requestRunCommandPermission" -> requestRunCommandPermission(result)
                "runTermuxCommand" -> {
                    val path = call.argument<String>("path")
                    val arguments = call.argument<List<String>>("arguments") ?: emptyList()
                    val background = call.argument<Boolean>("background") ?: true
                    val label = call.argument<String>("label")
                    if (path == null) {
                        result.error("invalid_args", "path is required", null)
                    } else {
                        result.success(runTermuxCommand(path, arguments, background, label))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isTermuxInstalled(): Boolean {
        return try {
            packageManager.getPackageInfo(termuxPackage, 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }

    /// Launches Termux itself in the foreground, e.g. so the user can type
    /// the one manual `allow-external-apps` command, or watch an
    /// interactive Tailscale login. Returns false if Termux isn't
    /// installed or has no launch intent.
    private fun openTermux(): Boolean {
        if (!isTermuxInstalled()) return false
        val intent = packageManager.getLaunchIntentForPackage(termuxPackage) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        return true
    }

    private fun openTermuxInstallPage() {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://f-droid.org/packages/com.termux/"))
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    private fun hasRunCommandPermission(): Boolean {
        return ContextCompat.checkSelfPermission(this, runCommandPermission) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestRunCommandPermission(result: Result) {
        if (hasRunCommandPermission()) {
            result.success(true)
            return
        }
        // Only one request can be in flight at a time; last caller wins,
        // which matches how the wizard uses this (one screen, one button).
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(this, arrayOf(runCommandPermission), runCommandRequestCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == runCommandRequestCode) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    /// Fires Termux's RUN_COMMAND intent. Fire-and-forget: Termux does not
    /// report completion back through this call, so callers must poll
    /// control-api separately to learn when a command finished. Returns
    /// false (without crashing) if Termux isn't installed, the RUN_COMMAND
    /// permission wasn't granted, or Termux itself rejects the intent (e.g.
    /// `allow-external-apps` isn't set in termux.properties).
    private fun runTermuxCommand(path: String, arguments: List<String>, background: Boolean, label: String?): Boolean {
        if (!isTermuxInstalled() || !hasRunCommandPermission()) return false
        return try {
            val intent = Intent()
            intent.setClassName(termuxPackage, "com.termux.app.RunCommandService")
            intent.action = "com.termux.RUN_COMMAND"
            intent.putExtra("com.termux.RUN_COMMAND_PATH", path)
            intent.putExtra("com.termux.RUN_COMMAND_ARGUMENTS", arguments.toTypedArray())
            intent.putExtra("com.termux.RUN_COMMAND_WORKDIR", "/data/data/com.termux/files/home")
            intent.putExtra("com.termux.RUN_COMMAND_BACKGROUND", background)
            if (label != null) intent.putExtra("com.termux.RUN_COMMAND_COMMAND_LABEL", label)
            if (!background) {
                // Switch to the new foreground session so the user sees it
                // (used for the interactive Tailscale login step).
                intent.putExtra("com.termux.RUN_COMMAND_SESSION_ACTION", "0")
            }
            ContextCompat.startForegroundService(this, intent)
            true
        } catch (e: Exception) {
            // Termux denied the intent (permission not granted,
            // allow-external-apps unset, service not found, etc). Don't
            // crash the app — let the Dart side show an error instead.
            false
        }
    }
}
