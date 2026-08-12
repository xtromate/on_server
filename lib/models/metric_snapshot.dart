/// One point-in-time snapshot from GET /api/metrics.
class MetricSnapshot {
  final CpuLoad cpu;
  final MemInfo mem;
  final DiskInfo disk;
  final BatteryInfo? battery;
  final DateTime timestamp;

  const MetricSnapshot({
    required this.cpu,
    required this.mem,
    required this.disk,
    this.battery,
    required this.timestamp,
  });

  factory MetricSnapshot.fromJson(Map<String, dynamic> json) {
    return MetricSnapshot(
      cpu: CpuLoad.fromJson(json['cpu'] as Map<String, dynamic>? ?? const {}),
      mem: MemInfo.fromJson(json['mem'] as Map<String, dynamic>? ?? const {}),
      disk: DiskInfo.fromJson(json['disk'] as Map<String, dynamic>? ?? const {}),
      battery: json['battery'] != null ? BatteryInfo.fromJson(json['battery'] as Map<String, dynamic>) : null,
      timestamp: json['timestamp'] != null
          ? (DateTime.tryParse(json['timestamp'].toString()) ??
              DateTime.fromMillisecondsSinceEpoch((json['timestamp'] as num).toInt()))
          : DateTime.now(),
    );
  }
}

class CpuLoad {
  final double load1;
  final double load5;
  final double load15;

  const CpuLoad({required this.load1, required this.load5, required this.load15});

  factory CpuLoad.fromJson(Map<String, dynamic> json) {
    return CpuLoad(
      load1: (json['load1'] as num?)?.toDouble() ?? 0,
      load5: (json['load5'] as num?)?.toDouble() ?? 0,
      load15: (json['load15'] as num?)?.toDouble() ?? 0,
    );
  }
}

class MemInfo {
  final int totalKb;
  final int usedKb;
  final int freeKb;

  const MemInfo({required this.totalKb, required this.usedKb, required this.freeKb});

  factory MemInfo.fromJson(Map<String, dynamic> json) {
    return MemInfo(
      totalKb: (json['totalKb'] as num?)?.toInt() ?? 0,
      usedKb: (json['usedKb'] as num?)?.toInt() ?? 0,
      freeKb: (json['freeKb'] as num?)?.toInt() ?? 0,
    );
  }

  double get usedFraction => totalKb == 0 ? 0 : (usedKb / totalKb).clamp(0, 1);
}

class DiskInfo {
  final int totalKb;
  final int usedKb;
  final int freeKb;
  final String mountPath;

  const DiskInfo({
    required this.totalKb,
    required this.usedKb,
    required this.freeKb,
    required this.mountPath,
  });

  factory DiskInfo.fromJson(Map<String, dynamic> json) {
    return DiskInfo(
      totalKb: (json['totalKb'] as num?)?.toInt() ?? 0,
      usedKb: (json['usedKb'] as num?)?.toInt() ?? 0,
      freeKb: (json['freeKb'] as num?)?.toInt() ?? 0,
      mountPath: json['mountPath'] as String? ?? '',
    );
  }

  double get usedFraction => totalKb == 0 ? 0 : (usedKb / totalKb).clamp(0, 1);
}

class BatteryInfo {
  final int percentage;
  final String status;
  final double? temperature;

  const BatteryInfo({required this.percentage, required this.status, this.temperature});

  factory BatteryInfo.fromJson(Map<String, dynamic> json) {
    return BatteryInfo(
      percentage: (json['percentage'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'unknown',
      temperature: (json['temperature'] as num?)?.toDouble(),
    );
  }
}
