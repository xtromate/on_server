/// A user-deployed backend, managed by control-api's Apps feature — the
/// flagship "deploy my backend, reach it from anywhere" flow.
class AppDeployment {
  final String name;
  final String repoUrl;
  final String? branch;
  final String? installCommand;
  final String startCommand;
  final int port;
  final String status; // "running" | "stopped" | "unknown"
  final int? pid;
  final String url;
  final DateTime? createdAt;

  const AppDeployment({
    required this.name,
    required this.repoUrl,
    this.branch,
    this.installCommand,
    required this.startCommand,
    required this.port,
    required this.status,
    this.pid,
    required this.url,
    this.createdAt,
  });

  factory AppDeployment.fromJson(Map<String, dynamic> json) {
    return AppDeployment(
      name: json['name'] as String,
      repoUrl: json['repoUrl'] as String? ?? '',
      branch: json['branch'] as String?,
      installCommand: json['installCommand'] as String?,
      startCommand: json['startCommand'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'unknown',
      pid: (json['pid'] as num?)?.toInt(),
      url: json['url'] as String? ?? '',
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'].toString()) : null,
    );
  }

  bool get isRunning => status == 'running';
}
