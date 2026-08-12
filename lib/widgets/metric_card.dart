import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/palette.dart';

/// A dashboard stat tile. Two forms, per the dataviz form heuristic:
///  - a **meter** (ratio against a limit — CPU/mem/disk usage), single hue,
///    fill color-coded by how close to the limit the value is
///  - a **sparkline** (trend over time — load average history), one thin
///    2px line in the sequential hue, no axes/gridlines (a stat tile, not a
///    full chart)
class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final double? fraction; // 0..1, meter form
  final List<double>? trend; // sparkline form
  final Color? accentOverride;
  final IconData? icon;

  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.fraction,
    this.trend,
    this.accentOverride,
    this.icon,
  });

  Color _fractionColor(BuildContext context, double f) {
    // Sequential ramp reserved for magnitude; past healthy thresholds we
    // hand off to the fixed status palette (always paired with the label
    // already on this tile, never color alone).
    if (f >= 0.9) return VizPalette.statusCritical;
    if (f >= 0.75) return VizPalette.statusWarning;
    return VizPalette.sequential(context);
  }

  @override
  Widget build(BuildContext context) {
    final track = VizPalette.sequentialTrack(context);
    final ink = VizPalette.primaryInk(context);
    final muted = VizPalette.secondaryInk(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VizPalette.surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: VizPalette.gridline(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: muted),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(color: ink, fontSize: 24, fontWeight: FontWeight.w700),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: TextStyle(color: muted, fontSize: 12)),
          ],
          if (fraction != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction!.clamp(0, 1),
                minHeight: 8,
                backgroundColor: track,
                valueColor: AlwaysStoppedAnimation(accentOverride ?? _fractionColor(context, fraction!)),
              ),
            ),
          ],
          if (trend != null && trend!.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: _Sparkline(values: trend!, color: accentOverride ?? VizPalette.sequential(context)),
            ),
          ],
        ],
      ),
    );
  }
}

class _Sparkline extends StatelessWidget {
  final List<double> values;
  final Color color;

  const _Sparkline({required this.values, required this.color});

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return const SizedBox.shrink();
    }
    final spots = [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])];
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY).abs() < 0.01 ? 1.0 : (maxY - minY) * 0.15;

    return LineChart(
      LineChartData(
        minY: minY - pad,
        maxY: maxY + pad,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: color,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.12)),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }
}
