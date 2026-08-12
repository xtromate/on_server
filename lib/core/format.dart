import 'package:intl/intl.dart';

/// Small formatting helpers shared across screens/widgets.
class Fmt {
  Fmt._();

  static final _decimal = NumberFormat('#,##0.0');
  static final _dateTime = DateFormat('MMM d, HH:mm');

  static String kb(int kb) {
    final bytes = kb * 1024;
    return bytesStr(bytes);
  }

  static String bytesStr(num bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    return '${_decimal.format(value)} ${units[unitIndex]}';
  }

  static String uptime(int? seconds) {
    if (seconds == null) return '—';
    final d = Duration(seconds: seconds);
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }

  static String dateTime(DateTime? dt) {
    if (dt == null) return '—';
    return _dateTime.format(dt.toLocal());
  }
}
