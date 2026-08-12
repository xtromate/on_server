import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the user-configured connection to the control-api (host, port,
/// bearer token), persisted via [SharedPreferences]. A [ChangeNotifier] so
/// the rest of the app (API client, screens) can react when the user
/// reconnects to a different phone or updates the token.
class ConnectionSettings extends ChangeNotifier {
  static const _keyHost = 'connection.host';
  static const _keyPort = 'connection.port';
  static const _keyToken = 'connection.token';

  static const int defaultPort = 8420;

  String _host = '';
  int _port = defaultPort;
  String _token = '';
  bool _loaded = false;

  String get host => _host;
  int get port => _port;
  String get token => _token;
  bool get loaded => _loaded;

  /// True once the user has entered enough to attempt a connection.
  bool get isConfigured => _host.trim().isNotEmpty && _token.trim().isNotEmpty;

  String get baseUrl => 'http://$_host:$_port';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _host = prefs.getString(_keyHost) ?? '';
    _port = prefs.getInt(_keyPort) ?? defaultPort;
    _token = prefs.getString(_keyToken) ?? '';
    _loaded = true;
    notifyListeners();
  }

  Future<void> update({required String host, required int port, required String token}) async {
    _host = host.trim();
    _port = port;
    _token = token.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyHost, _host);
    await prefs.setInt(_keyPort, _port);
    await prefs.setString(_keyToken, _token);
    notifyListeners();
  }

  Future<void> clear() async {
    _host = '';
    _port = defaultPort;
    _token = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyHost);
    await prefs.remove(_keyPort);
    await prefs.remove(_keyToken);
    notifyListeners();
  }
}
