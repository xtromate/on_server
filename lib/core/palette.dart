import 'package:flutter/material.dart';

/// Chart/status color roles, per the project's dataviz palette (see the
/// dataviz skill). Light/dark values are validated pairs — never derive one
/// from the other at runtime, always pick the mode-correct step.
class VizPalette {
  VizPalette._();

  static bool _isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

  // Chart chrome
  static Color surface(BuildContext context) => _isDark(context) ? const Color(0xFF1A1A19) : const Color(0xFFFCFCFB);
  static Color primaryInk(BuildContext context) => _isDark(context) ? const Color(0xFFFFFFFF) : const Color(0xFF0B0B0B);
  static Color secondaryInk(BuildContext context) => _isDark(context) ? const Color(0xFFC3C2B7) : const Color(0xFF52514E);
  static const Color mutedInk = Color(0xFF898781);
  static Color gridline(BuildContext context) => _isDark(context) ? const Color(0xFF2C2C2A) : const Color(0xFFE1E0D9);
  static Color baseline(BuildContext context) => _isDark(context) ? const Color(0xFF383835) : const Color(0xFFC3C2B7);

  // Sequential (blue) — magnitude. Used for meters/sparklines (single hue).
  static Color sequential(BuildContext context) => _isDark(context) ? const Color(0xFF3987E5) : const Color(0xFF2A78D6);
  static Color sequentialTrack(BuildContext context) => _isDark(context) ? const Color(0xFF2C2C2A) : const Color(0xFFE1E0D9);

  // Categorical slot 2 (orange) — used when a second sequential series
  // appears alongside the first (e.g. disk next to memory).
  static Color sequentialAlt(BuildContext context) => _isDark(context) ? const Color(0xFFD95926) : const Color(0xFFEB6834);

  // Status palette — fixed, never themed; always paired with icon + label.
  static const Color statusGood = Color(0xFF0CA30C);
  static const Color statusWarning = Color(0xFFFAB219);
  static const Color statusSerious = Color(0xFFEC835A);
  static const Color statusCritical = Color(0xFFD03B3B);
}
