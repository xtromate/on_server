import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../core/connection_settings.dart';

/// Host/port/token entry with a "test connection" button that hits
/// GET /api/health directly (no auth required for that route) using
/// whatever is currently typed, independent of what's been saved.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

enum _TestState { idle, testing, ok, failed }

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _tokenController;

  _TestState _testState = _TestState.idle;
  String? _testMessage;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<ConnectionSettings>();
    _hostController = TextEditingController(text: settings.host);
    _portController = TextEditingController(
      text: (settings.port == 0 ? ConnectionSettings.defaultPort : settings.port).toString(),
    );
    _tokenController = TextEditingController(text: settings.token);
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  int get _port => int.tryParse(_portController.text.trim()) ?? ConnectionSettings.defaultPort;

  Future<void> _testConnection() async {
    if (_hostController.text.trim().isEmpty) return;
    setState(() {
      _testState = _TestState.testing;
      _testMessage = null;
    });
    final uri = Uri.parse('http://${_hostController.text.trim()}:$_port/api/health');
    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        if (body is Map && body['ok'] == true) {
          setState(() {
            _testState = _TestState.ok;
            _testMessage = 'Connected — server time ${body['time']}';
          });
          return;
        }
      }
      setState(() {
        _testState = _TestState.failed;
        _testMessage = 'Unexpected response (${resp.statusCode})';
      });
    } on SocketException catch (e) {
      setState(() {
        _testState = _TestState.failed;
        _testMessage = 'Could not reach host: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _testState = _TestState.failed;
        _testMessage = 'Failed: $e';
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final settings = context.read<ConnectionSettings>();
    await settings.update(
      host: _hostController.text.trim(),
      port: _port,
      token: _tokenController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Connection settings saved')),
    );
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect to your phone')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter the control-api address running in Termux on your phone — '
                  'a LAN IP, Tailscale address, or "localhost" if this app runs on the phone itself.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _hostController,
                  decoration: const InputDecoration(
                    labelText: 'Host',
                    hintText: '100.x.x.x or 192.168.x.x or localhost',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Host is required' : null,
                  onChanged: (_) => setState(() => _testState = _TestState.idle),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _portController,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    if (n == null || n <= 0 || n > 65535) return 'Enter a valid port';
                    return null;
                  },
                  onChanged: (_) => setState(() => _testState = _TestState.idle),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _tokenController,
                  decoration: const InputDecoration(
                    labelText: 'Bearer token',
                    hintText: 'Printed by setup-services.sh',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Token is required' : null,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _testState == _TestState.testing ? null : _testConnection,
                      icon: _testState == _TestState.testing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering),
                      label: const Text('Test connection'),
                    ),
                    const SizedBox(width: 12),
                    if (_testMessage != null)
                      Expanded(
                        child: Text(
                          _testMessage!,
                          style: TextStyle(
                            color: _testState == _TestState.ok
                                ? Colors.green
                                : (_testState == _TestState.failed ? Colors.red : null),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text('Save & continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
