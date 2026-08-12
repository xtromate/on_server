import 'package:flutter/services.dart';

/// Thin wrapper around the `on_server/termux` platform channel (see
/// MainActivity.kt) that drives Termux's RUN_COMMAND API. Used by the Setup
/// Wizard to automate the Termux side of getting control-api running.
///
/// `runCommand` is fire-and-forget: Termux does not report command
/// completion back through the channel, so callers that need to know when a
/// command finished must poll control-api's HTTP API separately.
class TermuxBridge {
  static const _channel = MethodChannel('on_server/termux');

  Future<bool> isInstalled() async {
    return (await _channel.invokeMethod<bool>('isTermuxInstalled')) ?? false;
  }

  /// Launches Termux itself in the foreground.
  Future<void> openTermux() async {
    await _channel.invokeMethod('openTermux');
  }

  /// Opens Termux's F-Droid page in a browser for installation.
  Future<void> openInstallPage() async {
    await _channel.invokeMethod('openTermuxInstallPage');
  }

  /// Whether the dangerous `com.termux.permission.RUN_COMMAND` permission
  /// has already been granted.
  Future<bool> hasRunCommandPermission() async {
    return (await _channel.invokeMethod<bool>('hasRunCommandPermission')) ?? false;
  }

  /// Prompts the user for `com.termux.permission.RUN_COMMAND` if not
  /// already granted. Must be awaited (and granted) before the first
  /// [runCommand] call — Android denies the intent silently otherwise.
  Future<bool> requestRunCommandPermission() async {
    return (await _channel.invokeMethod<bool>('requestRunCommandPermission')) ?? false;
  }

  /// Fires a Termux RUN_COMMAND intent. Returns false if Termux rejected it
  /// (not installed, permission not granted, or `allow-external-apps` not
  /// set in termux.properties) — true only means the intent was accepted,
  /// not that the command succeeded.
  Future<bool> runCommand({
    required String path,
    required List<String> arguments,
    required bool background,
    String? label,
  }) async {
    final ok = await _channel.invokeMethod<bool>('runTermuxCommand', {
      'path': path,
      'arguments': arguments,
      'background': background,
      'label': ?label,
    });
    return ok ?? false;
  }
}
