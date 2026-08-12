/// Telegram bot config/status from GET|PUT /api/bots/telegram. The raw
/// token is write-only — the server only ever reports whether one is set.
class BotStatus {
  final bool enabled;
  final bool hasToken;
  final String status;

  const BotStatus({required this.enabled, required this.hasToken, required this.status});

  factory BotStatus.fromJson(Map<String, dynamic> json) {
    return BotStatus(
      enabled: json['enabled'] as bool? ?? false,
      hasToken: json['hasToken'] as bool? ?? false,
      status: json['status'] as String? ?? 'unknown',
    );
  }
}
