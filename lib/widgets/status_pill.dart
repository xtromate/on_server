import 'package:flutter/material.dart';

import '../core/palette.dart';

/// A small status indicator: icon + label, never color alone (status color
/// is reserved and always paired per the dataviz palette rules).
class StatusPill extends StatelessWidget {
  final String status;

  const StatusPill({super.key, required this.status});

  ({Color color, IconData icon, String label}) _spec(String status) {
    switch (status) {
      case 'running':
        return (color: VizPalette.statusGood, icon: Icons.check_circle, label: 'Running');
      case 'stopped':
        return (color: VizPalette.statusCritical, icon: Icons.stop_circle, label: 'Stopped');
      default:
        return (color: VizPalette.statusWarning, icon: Icons.help, label: 'Unknown');
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: spec.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: spec.color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(spec.icon, size: 14, color: spec.color),
          const SizedBox(width: 6),
          Text(
            spec.label,
            style: TextStyle(color: spec.color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
