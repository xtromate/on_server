import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/app_deployment.dart';
import '../models/bot_status.dart';
import '../models/file_entry.dart';
import '../models/metric_snapshot.dart';
import '../models/service_status.dart';
import 'connection_settings.dart';

/// Thrown for any non-2xx response. Carries the server's `error` message
/// (from the `{ok:false, error:"..."}` shape) when available, otherwise a
/// generic description, plus the HTTP status code.
class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Thrown when the request never reached the server (DNS/connect/timeout).
class ApiConnectionException implements Exception {
  final String message;
  ApiConnectionException(this.message);

  @override
  String toString() => message;
}

/// Thin HTTP wrapper around control-api's REST contract. Base URL and
/// bearer token come from [ConnectionSettings]; one method per endpoint.
class ApiClient {
  final ConnectionSettings settings;
  final http.Client _client;

  ApiClient(this.settings, {http.Client? client}) : _client = client ?? http.Client();

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse(settings.baseUrl);
    return base.replace(
      path: path,
      queryParameters: query?.map((k, v) => MapEntry(k, v.toString())),
    );
  }

  Map<String, String> get _authHeaders => {
        'Authorization': 'Bearer ${settings.token}',
      };

  Future<T> _send<T>(Future<http.Response> Function() request, T Function(dynamic body) onOk) async {
    http.Response resp;
    try {
      resp = await request().timeout(const Duration(seconds: 15));
    } on SocketException catch (e) {
      throw ApiConnectionException('Could not reach ${settings.host}:${settings.port} — ${e.message}');
    } on HttpException catch (e) {
      throw ApiConnectionException(e.message);
    } catch (e) {
      throw ApiConnectionException('Request failed: $e');
    }

    dynamic decoded;
    try {
      decoded = resp.body.isEmpty ? null : jsonDecode(resp.body);
    } catch (_) {
      decoded = null;
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final message = (decoded is Map && decoded['error'] != null)
          ? decoded['error'].toString()
          : 'Request failed (${resp.statusCode})';
      throw ApiException(resp.statusCode, message);
    }

    return onOk(decoded);
  }

  // ---- Health -------------------------------------------------------

  Future<bool> health() {
    return _send(
      () => _client.get(_uri('/api/health')),
      (body) => body is Map && body['ok'] == true,
    );
  }

  // ---- Services -------------------------------------------------------

  Future<List<ServiceStatus>> services() {
    return _send(
      () => _client.get(_uri('/api/services'), headers: _authHeaders),
      (body) {
        final list = (body as Map)['services'] as List? ?? [];
        return list.map((e) => ServiceStatus.fromJson(e as Map<String, dynamic>)).toList();
      },
    );
  }

  Future<ServiceStatus> serviceAction(String name, String action) {
    return _send(
      () => _client.post(_uri('/api/services/$name/$action'), headers: _authHeaders),
      (body) => ServiceStatus.fromJson((body as Map)['service'] as Map<String, dynamic>),
    );
  }

  Future<List<String>> serviceLogs(String name, {int lines = 200}) {
    return _send(
      () => _client.get(_uri('/api/services/$name/logs', {'lines': lines}), headers: _authHeaders),
      (body) => ((body as Map)['lines'] as List? ?? []).map((e) => e.toString()).toList(),
    );
  }

  // ---- Apps -------------------------------------------------------

  Future<List<AppDeployment>> apps() {
    return _send(
      () => _client.get(_uri('/api/apps'), headers: _authHeaders),
      (body) {
        final list = (body as Map)['apps'] as List? ?? [];
        return list.map((e) => AppDeployment.fromJson(e as Map<String, dynamic>)).toList();
      },
    );
  }

  Future<AppDeployment> createApp({
    required String name,
    required String repoUrl,
    String? branch,
    String? installCommand,
    required String startCommand,
    required int port,
    Map<String, String>? env,
  }) {
    final payload = <String, dynamic>{
      'name': name,
      'repoUrl': repoUrl,
      'startCommand': startCommand,
      'port': port,
      if (branch != null && branch.isNotEmpty) 'branch': branch,
      if (installCommand != null && installCommand.isNotEmpty) 'installCommand': installCommand,
      if (env != null && env.isNotEmpty) 'env': env,
    };
    return _send(
      () => _client.post(
        _uri('/api/apps'),
        headers: {..._authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ),
      (body) => AppDeployment.fromJson((body as Map)['app'] as Map<String, dynamic>),
    );
  }

  Future<AppDeployment> redeployApp(String name) {
    return _send(
      () => _client.post(_uri('/api/apps/$name/redeploy'), headers: _authHeaders),
      (body) => AppDeployment.fromJson((body as Map)['app'] as Map<String, dynamic>),
    );
  }

  Future<AppDeployment> appAction(String name, String action) {
    return _send(
      () => _client.post(_uri('/api/apps/$name/$action'), headers: _authHeaders),
      (body) => AppDeployment.fromJson((body as Map)['app'] as Map<String, dynamic>),
    );
  }

  Future<List<String>> appLogs(String name, {int lines = 200}) {
    return _send(
      () => _client.get(_uri('/api/apps/$name/logs', {'lines': lines}), headers: _authHeaders),
      (body) => ((body as Map)['lines'] as List? ?? []).map((e) => e.toString()).toList(),
    );
  }

  Future<void> deleteApp(String name, {bool removeFiles = false}) {
    return _send(
      () => _client.delete(
        _uri('/api/apps/$name', {'removeFiles': removeFiles}),
        headers: _authHeaders,
      ),
      (_) {},
    );
  }

  // ---- Files -------------------------------------------------------

  Future<List<FileEntry>> listFiles(String path) {
    return _send(
      () => _client.get(_uri('/api/files', {'path': path}), headers: _authHeaders),
      (body) {
        final list = (body as Map)['entries'] as List? ?? [];
        return list.map((e) => FileEntry.fromJson(e as Map<String, dynamic>)).toList();
      },
    );
  }

  Future<void> mkdir(String path) {
    return _send(
      () => _client.post(
        _uri('/api/files/mkdir'),
        headers: {..._authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({'path': path}),
      ),
      (_) {},
    );
  }

  Future<void> uploadFile(String destDir, String filename, List<int> bytes) {
    return _send(
      () async {
        final req = http.MultipartRequest('POST', _uri('/api/files/upload', {'path': destDir}));
        req.headers.addAll(_authHeaders);
        req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
        final streamed = await _client.send(req);
        return http.Response.fromStream(streamed);
      },
      (_) {},
    );
  }

  /// Downloads raw file bytes. Handled separately from [_send] because a
  /// successful response here is a byte stream, not JSON.
  Future<List<int>> downloadFile(String path) async {
    http.Response resp;
    try {
      resp = await _client
          .get(_uri('/api/files/download', {'path': path}), headers: _authHeaders)
          .timeout(const Duration(seconds: 30));
    } on SocketException catch (e) {
      throw ApiConnectionException('Could not reach ${settings.host}:${settings.port} — ${e.message}');
    } catch (e) {
      throw ApiConnectionException('Request failed: $e');
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      String message = 'Download failed (${resp.statusCode})';
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map && decoded['error'] != null) message = decoded['error'].toString();
      } catch (_) {}
      throw ApiException(resp.statusCode, message);
    }
    return resp.bodyBytes;
  }

  Future<void> deleteFile(String path) {
    return _send(
      () => _client.delete(_uri('/api/files', {'path': path}), headers: _authHeaders),
      (_) {},
    );
  }

  // ---- Metrics -------------------------------------------------------

  Future<MetricSnapshot> metrics() {
    return _send(
      () => _client.get(_uri('/api/metrics'), headers: _authHeaders),
      (body) => MetricSnapshot.fromJson(body as Map<String, dynamic>),
    );
  }

  // ---- Bots -------------------------------------------------------

  Future<BotStatus> telegramBotStatus() {
    return _send(
      () => _client.get(_uri('/api/bots/telegram'), headers: _authHeaders),
      (body) => BotStatus.fromJson(body as Map<String, dynamic>),
    );
  }

  Future<BotStatus> updateTelegramBot({String? token, required bool enabled}) {
    final payload = <String, dynamic>{
      'enabled': enabled,
      if (token != null && token.isNotEmpty) 'token': token,
    };
    return _send(
      () => _client.put(
        _uri('/api/bots/telegram'),
        headers: {..._authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ),
      (body) => BotStatus.fromJson((body as Map)['bot'] as Map<String, dynamic>),
    );
  }

  void dispose() {
    _client.close();
  }
}
