import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/connection_settings.dart';
import '../core/format.dart';
import '../core/palette.dart';
import '../models/metric_snapshot.dart';
import '../widgets/metric_card.dart';

/// Connection status + live metric cards. Polls GET /api/metrics on a
/// timer while visible; pauses when another tab is active.
class DashboardScreen extends StatefulWidget {
  final bool active;
  const DashboardScreen({super.key, required this.active});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Timer? _timer;
  MetricSnapshot? _snapshot;
  String? _error;
  bool _loading = false;
  final List<double> _load1History = [];

  static const _pollInterval = Duration(seconds: 4);
  static const _maxHistory = 30;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
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
      final snap = await client.metrics();
      if (!mounted) return;
      setState(() {
        _snapshot = snap;
        _error = null;
        _loading = false;
        _load1History.add(snap.cpu.load1);
        if (_load1History.length > _maxHistory) {
          _load1History.removeAt(0);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException || e is ApiConnectionException ? e.toString() : 'Failed to load metrics';
        _loading = false;
      });
    } finally {
      client.dispose();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<ConnectionSettings>();
    final snap = _snapshot;

    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Icon(
                _error == null ? Icons.check_circle : Icons.error,
                color: _error == null ? VizPalette.statusGood : VizPalette.statusCritical,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _error == null ? 'Connected to ${settings.host}:${settings.port}' : _error!,
                  style: TextStyle(color: _error == null ? null : VizPalette.statusCritical),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_loading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 12),
          if (snap == null && _error == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (snap != null)
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.35,
              children: [
                MetricCard(
                  title: 'CPU LOAD',
                  value: snap.cpu.load1.toStringAsFixed(2),
                  subtitle: '5m ${snap.cpu.load5.toStringAsFixed(2)} · 15m ${snap.cpu.load15.toStringAsFixed(2)}',
                  trend: List.of(_load1History),
                  icon: Icons.speed,
                ),
                MetricCard(
                  title: 'MEMORY',
                  value: '${(snap.mem.usedFraction * 100).toStringAsFixed(0)}%',
                  subtitle: '${Fmt.kb(snap.mem.usedKb)} / ${Fmt.kb(snap.mem.totalKb)}',
                  fraction: snap.mem.usedFraction,
                  icon: Icons.memory,
                ),
                MetricCard(
                  title: 'DISK',
                  value: '${(snap.disk.usedFraction * 100).toStringAsFixed(0)}%',
                  subtitle: '${Fmt.kb(snap.disk.usedKb)} / ${Fmt.kb(snap.disk.totalKb)}'
                      '${snap.disk.mountPath.isNotEmpty ? ' · ${snap.disk.mountPath}' : ''}',
                  fraction: snap.disk.usedFraction,
                  icon: Icons.storage,
                ),
                if (snap.battery != null)
                  MetricCard(
                    title: 'BATTERY',
                    value: '${snap.battery!.percentage}%',
                    subtitle: '${snap.battery!.status}'
                        '${snap.battery!.temperature != null ? ' · ${snap.battery!.temperature!.toStringAsFixed(1)}°C' : ''}',
                    fraction: snap.battery!.percentage / 100,
                    icon: snap.battery!.status.toLowerCase().contains('charg') ? Icons.bolt : Icons.battery_std,
                  )
                else
                  const MetricCard(
                    title: 'BATTERY',
                    value: 'N/A',
                    subtitle: 'termux-api not available',
                    icon: Icons.battery_unknown,
                  ),
              ],
            ),
          if (snap != null) ...[
            const SizedBox(height: 8),
            Text(
              'Last updated ${Fmt.dateTime(snap.timestamp)}',
              style: TextStyle(color: VizPalette.secondaryInk(context), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
