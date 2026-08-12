import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/connection_settings.dart';
import '../models/app_deployment.dart';
import '../widgets/service_tile.dart';
import 'service_logs_screen.dart';

final RegExp _slugPattern = RegExp(r'^[a-zA-Z0-9_-]+$');

/// FLAGSHIP screen: deployed backends, a prominent "deploy new app" flow,
/// and per-app lifecycle actions. This is the centerpiece of the app —
/// "run my backend from my phone, reach it from anywhere."
class AppsScreen extends StatefulWidget {
  final bool active;
  const AppsScreen({super.key, required this.active});

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  Timer? _timer;
  List<AppDeployment> _apps = [];
  String? _error;
  bool _loading = false;
  final Set<String> _busy = {};

  static const _pollInterval = Duration(seconds: 5);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant AppsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  void _syncTimer() {
    if (widget.active && _timer == null) {
      _fetch();
      _timer = Timer.periodic(_pollInterval, (_) => _fetch());
    } else if (!widget.active && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    final settings = context.read<ConnectionSettings>();
    if (!settings.isConfigured) return;
    final client = ApiClient(settings);
    setState(() => _loading = true);
    try {
      final list = await client.apps();
      if (!mounted) return;
      setState(() {
        _apps = list;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    } finally {
      client.dispose();
    }
  }

  Future<void> _act(String name, Future<AppDeployment> Function(ApiClient) action) async {
    final settings = context.read<ConnectionSettings>();
    final client = ApiClient(settings);
    setState(() => _busy.add(name));
    try {
      await action(client);
      await _fetch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      client.dispose();
      if (mounted) setState(() => _busy.remove(name));
    }
  }

  Future<void> _delete(AppDeployment app) async {
    final removeFiles = await showDialog<bool>(
      context: context,
      builder: (context) => _DeleteAppDialog(name: app.name),
    );
    if (removeFiles == null) return;
    await _act(app.name, (client) async {
      await client.deleteApp(app.name, removeFiles: removeFiles);
      return app;
    });
    await _fetch();
  }

  Future<void> _openDeployForm() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _DeployAppSheet(),
    );
    if (created == true) _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _error != null && _apps.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 40),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(onPressed: _fetch, icon: const Icon(Icons.refresh), label: const Text('Retry')),
                  ],
                ),
              ),
            )
          : _apps.isEmpty && !_loading
              ? _EmptyState(onDeploy: _openDeployForm)
              : RefreshIndicator(
                  onRefresh: _fetch,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                    itemCount: _apps.length,
                    itemBuilder: (context, i) {
                      final app = _apps[i];
                      return ServiceTile(
                        name: app.name,
                        status: app.status,
                        subtitle: '${app.repoUrl}${app.branch != null ? ' @ ${app.branch}' : ''}',
                        busy: _busy.contains(app.name),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ServiceLogsScreen(name: app.name, kind: LogKind.app),
                          ),
                        ),
                        onStart: () => _act(app.name, (c) => c.appAction(app.name, 'start')),
                        onStop: () => _act(app.name, (c) => c.appAction(app.name, 'stop')),
                        onRestart: () => _act(app.name, (c) => c.appAction(app.name, 'restart')),
                        extraActions: [
                          OutlinedButton.icon(
                            onPressed: () => _act(app.name, (c) => c.redeployApp(app.name)),
                            icon: const Icon(Icons.cloud_sync, size: 16),
                            label: const Text('Redeploy'),
                            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _delete(app),
                            icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                            label: const Text('Delete', style: TextStyle(color: Colors.red)),
                            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                          ),
                          if (app.url.isNotEmpty)
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () async {
                                await Clipboard.setData(ClipboardData(text: app.url));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(content: Text('Copied ${app.url}')));
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.link, size: 14),
                                    const SizedBox(width: 4),
                                    Text(app.url, style: const TextStyle(fontSize: 12, decoration: TextDecoration.underline)),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.copy, size: 12),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openDeployForm,
        icon: const Icon(Icons.add),
        label: const Text('Deploy new app'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onDeploy;
  const _EmptyState({required this.onDeploy});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.rocket_launch_outlined, size: 48),
            const SizedBox(height: 12),
            Text('No apps deployed yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text(
              'Deploy a backend from a git repo and reach it from anywhere on your tailnet.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onDeploy, icon: const Icon(Icons.add), label: const Text('Deploy new app')),
          ],
        ),
      ),
    );
  }
}

class _DeleteAppDialog extends StatefulWidget {
  final String name;
  const _DeleteAppDialog({required this.name});

  @override
  State<_DeleteAppDialog> createState() => _DeleteAppDialogState();
}

class _DeleteAppDialogState extends State<_DeleteAppDialog> {
  bool _removeFiles = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Delete ${widget.name}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('This stops the process. Optionally remove the cloned files too.'),
          CheckboxListTile(
            value: _removeFiles,
            onChanged: (v) => setState(() => _removeFiles = v ?? false),
            title: const Text('Also delete files on disk'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_removeFiles),
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}

/// The "deploy new app" form: repo URL, branch, install command, start
/// command, port. Name is validated client-side as a safe slug too.
class _DeployAppSheet extends StatefulWidget {
  const _DeployAppSheet();

  @override
  State<_DeployAppSheet> createState() => _DeployAppSheetState();
}

class _DeployAppSheetState extends State<_DeployAppSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _repoUrl = TextEditingController();
  final _branch = TextEditingController();
  final _installCommand = TextEditingController();
  final _startCommand = TextEditingController();
  final _port = TextEditingController();
  bool _submitting = false;
  String? _submitError;

  @override
  void dispose() {
    _name.dispose();
    _repoUrl.dispose();
    _branch.dispose();
    _installCommand.dispose();
    _startCommand.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    final settings = context.read<ConnectionSettings>();
    final client = ApiClient(settings);
    try {
      await client.createApp(
        name: _name.text.trim(),
        repoUrl: _repoUrl.text.trim(),
        branch: _branch.text.trim().isEmpty ? null : _branch.text.trim(),
        installCommand: _installCommand.text.trim().isEmpty ? null : _installCommand.text.trim(),
        startCommand: _startCommand.text.trim(),
        port: int.parse(_port.text.trim()),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _submitError = e.toString());
    } finally {
      client.dispose();
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Deploy new app', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text('Clones a git repo, installs it, and starts it under pm2 on your phone.'),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name (slug)', hintText: 'my-api', border: OutlineInputBorder()),
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return 'Name is required';
                  if (!_slugPattern.hasMatch(value)) return 'Only letters, numbers, - and _';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _repoUrl,
                decoration: const InputDecoration(
                  labelText: 'Git repo URL',
                  hintText: 'https://github.com/you/your-backend.git',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Repo URL is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _branch,
                decoration: const InputDecoration(
                  labelText: 'Branch (optional)',
                  hintText: 'defaults to the repo default branch',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _installCommand,
                decoration: const InputDecoration(
                  labelText: 'Install command (optional)',
                  hintText: 'npm install / pip install -r requirements.txt',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _startCommand,
                decoration: const InputDecoration(
                  labelText: 'Start command',
                  hintText: 'npm start / node index.js',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Start command is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _port,
                decoration: const InputDecoration(labelText: 'Port', hintText: '3000', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  if (n == null || n <= 0 || n > 65535) return 'Enter a valid port';
                  return null;
                },
              ),
              if (_submitError != null) ...[
                const SizedBox(height: 12),
                Text(_submitError!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Deploy'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
