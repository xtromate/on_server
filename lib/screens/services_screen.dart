import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/connection_settings.dart';
import '../core/format.dart';
import '../models/service_status.dart';
import '../widgets/service_tile.dart';
import 'service_logs_screen.dart';

/// Built-in daemon (nginx/redis/postgresql/sshd) and process
/// (control-api/telegram-bot) list. Polls GET /api/services.
class ServicesScreen extends StatefulWidget {
  final bool active;
  const ServicesScreen({super.key, required this.active});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  Timer? _timer;
  List<ServiceStatus> _services = [];
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
  void didUpdateWidget(covariant ServicesScreen oldWidget) {
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

  Future<void> _fetch() async {
    final settings = context.read<ConnectionSettings>();
    if (!settings.isConfigured) return;
    final client = ApiClient(settings);
    setState(() => _loading = true);
    try {
      final list = await client.services();
      if (!mounted) return;
      setState(() {
        _services = list;
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

  Future<void> _act(String name, String action) async {
    final settings = context.read<ConnectionSettings>();
    final client = ApiClient(settings);
    setState(() => _busy.add(name));
    try {
      await client.serviceAction(name, action);
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

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _services.isEmpty) {
      return _ErrorState(message: _error!, onRetry: _fetch);
    }
    if (_services.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _services.length,
        itemBuilder: (context, i) {
          final s = _services[i];
          final parts = <String>[s.kind];
          if (s.pid != null) parts.add('pid ${s.pid}');
          if (s.uptimeSec != null) parts.add('up ${Fmt.uptime(s.uptimeSec)}');
          return ServiceTile(
            name: s.name,
            status: s.status,
            subtitle: parts.join(' · '),
            busy: _busy.contains(s.name),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ServiceLogsScreen(name: s.name, kind: LogKind.service),
              ),
            ),
            onStart: () => _act(s.name, 'start'),
            onStop: () => _act(s.name, 'stop'),
            onRestart: () => _act(s.name, 'restart'),
          );
        },
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
