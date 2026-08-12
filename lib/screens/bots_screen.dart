import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/connection_settings.dart';
import '../core/palette.dart';
import '../models/bot_status.dart';
import '../widgets/status_pill.dart';

/// Telegram bot config: write-only token field (the server never returns
/// the raw token, only whether one is set), enable toggle, live status.
class BotsScreen extends StatefulWidget {
  final bool active;
  const BotsScreen({super.key, required this.active});

  @override
  State<BotsScreen> createState() => _BotsScreenState();
}

class _BotsScreenState extends State<BotsScreen> {
  Timer? _timer;
  BotStatus? _status;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  final _tokenController = TextEditingController();

  static const _pollInterval = Duration(seconds: 5);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant BotsScreen oldWidget) {
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
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final settings = context.read<ConnectionSettings>();
    if (!settings.isConfigured) return;
    final client = ApiClient(settings);
    try {
      final status = await client.telegramBotStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _enabled = status.enabled;
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

  Future<void> _save() async {
    final settings = context.read<ConnectionSettings>();
    final client = ApiClient(settings);
    setState(() => _saving = true);
    try {
      final status = await client.updateTelegramBot(
        token: _tokenController.text.trim().isEmpty ? null : _tokenController.text.trim(),
        enabled: _enabled,
      );
      if (!mounted) return;
      setState(() {
        _status = status;
        _enabled = status.enabled;
        _tokenController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bot settings saved')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      client.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _status == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _fetch, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final status = _status;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.smart_toy),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('Telegram bot', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                    if (status != null) StatusPill(status: status.status),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      status?.hasToken == true ? Icons.check_circle : Icons.remove_circle_outline,
                      size: 16,
                      color: status?.hasToken == true ? VizPalette.statusGood : VizPalette.mutedInk,
                    ),
                    const SizedBox(width: 6),
                    Text(status?.hasToken == true ? 'Token is set' : 'No token set yet'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _tokenController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: status?.hasToken == true ? 'Replace token (leave blank to keep current)' : 'Bot token',
            hintText: 'From @BotFather',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
          title: const Text('Enabled'),
          subtitle: const Text('Polling mode — no public webhook needed'),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save),
          label: const Text('Save'),
        ),
      ],
    );
  }
}
