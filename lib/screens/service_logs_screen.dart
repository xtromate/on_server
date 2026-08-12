import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/connection_settings.dart';

enum LogKind { service, app }

/// Reusable log viewer for both GET /api/services/:name/logs and
/// GET /api/apps/:name/logs. Polls every few seconds while open.
class ServiceLogsScreen extends StatefulWidget {
  final String name;
  final LogKind kind;

  const ServiceLogsScreen({super.key, required this.name, required this.kind});

  @override
  State<ServiceLogsScreen> createState() => _ServiceLogsScreenState();
}

class _ServiceLogsScreenState extends State<ServiceLogsScreen> {
  Timer? _timer;
  List<String> _lines = [];
  String? _error;
  bool _loading = true;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _fetch());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final settings = context.read<ConnectionSettings>();
    final client = ApiClient(settings);
    try {
      final lines = widget.kind == LogKind.service
          ? await client.serviceLogs(widget.name, lines: 200)
          : await client.appLogs(widget.name, lines: 200);
      if (!mounted) return;
      setState(() {
        _lines = lines;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.name} logs'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetch),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _lines.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : Container(
                  color: Colors.black,
                  width: double.infinity,
                  child: _lines.isEmpty
                      ? const Center(child: Text('No log output yet', style: TextStyle(color: Colors.white54)))
                      : SelectionArea(
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(12),
                            itemCount: _lines.length,
                            itemBuilder: (context, i) => Text(
                              _lines[i],
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'monospace',
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                ),
    );
  }
}
