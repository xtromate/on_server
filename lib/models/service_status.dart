/// A built-in service managed by control-api: either a termux-services
/// "daemon" (nginx, redis, postgresql, sshd) or a pm2-managed "process"
/// (control-api, telegram-bot).
class ServiceStatus {
  final String name;
  final String kind; // "daemon" | "process"
  final String status; // "running" | "stopped" | "unknown"
  final int? uptimeSec;
  final int? pid;

  const ServiceStatus({
    required this.name,
    required this.kind,
    required this.status,
    this.uptimeSec,
    this.pid,
  });

  factory ServiceStatus.fromJson(Map<String, dynamic> json) {
    return ServiceStatus(
      name: json['name'] as String,
      kind: json['kind'] as String? ?? 'unknown',
      status: json['status'] as String? ?? 'unknown',
      uptimeSec: (json['uptimeSec'] as num?)?.toInt(),
      pid: (json['pid'] as num?)?.toInt(),
    );
  }

  bool get isRunning => status == 'running';
}
