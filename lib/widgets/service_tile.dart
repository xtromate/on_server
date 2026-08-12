import 'package:flutter/material.dart';

import 'status_pill.dart';

/// A row for one service or app: name, status pill, optional subtitle
/// (kind/uptime/pid/url), and start/stop/restart actions. Shared by
/// services_screen and apps_screen; tapping the tile opens logs.
class ServiceTile extends StatelessWidget {
  final String name;
  final String status;
  final String? subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onStart;
  final VoidCallback? onStop;
  final VoidCallback? onRestart;
  final List<Widget>? extraActions;
  final bool busy;

  const ServiceTile({
    super.key,
    required this.name,
    required this.status,
    this.subtitle,
    this.onTap,
    this.onStart,
    this.onStop,
    this.onRestart,
    this.extraActions,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final isRunning = status == 'running';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(status: status),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 10),
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: LinearProgressIndicator(minHeight: 3),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (onStart != null)
                      OutlinedButton.icon(
                        onPressed: isRunning ? null : onStart,
                        icon: const Icon(Icons.play_arrow, size: 16),
                        label: const Text('Start'),
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                      ),
                    if (onStop != null)
                      OutlinedButton.icon(
                        onPressed: isRunning ? onStop : null,
                        icon: const Icon(Icons.stop, size: 16),
                        label: const Text('Stop'),
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                      ),
                    if (onRestart != null)
                      OutlinedButton.icon(
                        onPressed: onRestart,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Restart'),
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                      ),
                    if (extraActions != null) ...extraActions!,
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
