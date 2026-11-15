import 'package:flutter/material.dart';

/// Design tokens copied from the Keel UI kit
/// (keel-pack/keel/tokens/design-tokens.json + index.html).
/// Edit colours here only — every screen reads from this file.
abstract final class KeelTokens {
  // Light
  static const Color bgLight = Color(0xFFE9EEF1);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color inkLight = Color(0xFF0D1B26);
  static const Color mutedLight = Color(0xFF7B8894);
  static const Color lineLight = Color(0xFFDCE3E8);
  static const Color accentLight = Color(0xFF0E7C86);
  static const Color success = Color(0xFF2E9C78);
  static const Color overdue = Color(0xFFE5604D);
  static const Color noTeam = Color(0xFF98A4AE);

  // Dark
  static const Color bgDark = Color(0xFF0A1118);
  static const Color cardDark = Color(0xFF142029);
  static const Color inkDark = Color(0xFFEAF1F5);
  static const Color mutedDark = Color(0xFF8696A3);
  static const Color lineDark = Color(0xFF22313C);
  static const Color accentDark = Color(0xFF3CC3CF);
  static const Color dialCardDark = Color(0xFF1B3340);

  // Team colour presets (in kit order)
  static const List<Color> teamPresets = [
    Color(0xFFE5604D), // coral
    Color(0xFF4F6BED), // indigo
    Color(0xFFE3A21A), // amber
    Color(0xFF2E9C78), // green
    Color(0xFF9B5DE5), // violet
    Color(0xFFD6478B), // pink
  ];

  // Radii
  static const double radiusCard = 22;
  static const double radiusSheet = 32;
  static const double radiusButton = 18;
  static const double radiusCheck = 9;

  // Motion (section 7 of the master prompt)
  static const Duration fadeFast = Duration(milliseconds: 180);
  static const Duration fade = Duration(milliseconds: 220);
  static const Duration fadeSlow = Duration(milliseconds: 260);
  static const Duration spring = Duration(milliseconds: 300);
  static const Duration stagger = Duration(milliseconds: 40);

  /// Spring-ish curve approximating stiffness ~300 / damping ~26.
  static const Curve springCurve = Curves.easeOutBack;
  static const Curve easeOut = Curves.easeOutCubic;

  static Color colorFromHex(String hex) {
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  static String hexOf(Color c) {
    return '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
  }

  /// 16% tint of [color] over [card] — the avatar fill from the kit.
  static Color tint(Color color, Color card) =>
      Color.alphaBlend(color.withValues(alpha: 0.16), card);

  /// 14% tint used for chips and tinted icon tiles.
  static Color tint14(Color color, Color card) =>
      Color.alphaBlend(color.withValues(alpha: 0.14), card);
}

extension KeelTheme on BuildContext {
  ThemeData get keelTheme => Theme.of(this);
  ColorScheme get scheme => Theme.of(this).colorScheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get bg => isDark ? KeelTokens.bgDark : KeelTokens.bgLight;
  Color get card => isDark ? KeelTokens.cardDark : KeelTokens.cardLight;
  Color get ink => isDark ? KeelTokens.inkDark : KeelTokens.inkLight;
  Color get muted => isDark ? KeelTokens.mutedDark : KeelTokens.mutedLight;
  Color get line => isDark ? KeelTokens.lineDark : KeelTokens.lineLight;
  Color get accent =>
      isDark ? KeelTokens.accentDark : KeelTokens.accentLight;
  Color get dialCard =>
      isDark ? KeelTokens.dialCardDark : KeelTokens.inkLight;
  Color get dialInk => isDark ? KeelTokens.inkDark : KeelTokens.bgLight;
}

ThemeData keelThemeData({
  required Brightness brightness,
  required Color accent,
}) {
  final isDark = brightness == Brightness.dark;
  final bg = isDark ? KeelTokens.bgDark : KeelTokens.bgLight;
  final card = isDark ? KeelTokens.cardDark : KeelTokens.cardLight;
  final ink = isDark ? KeelTokens.inkDark : KeelTokens.inkLight;
  final muted = isDark ? KeelTokens.mutedDark : KeelTokens.mutedLight;
  final line = isDark ? KeelTokens.lineDark : KeelTokens.lineLight;

  final base = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    scaffoldBackgroundColor: bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      primary: accent,
      surface: card,
      onSurface: ink,
    ),
    fontFamily: 'Inter',
    // Universal rule: no blue tap highlight / focus ring anywhere.
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
    textTheme: TextTheme(
      // Display / large titles: Nunito 800, 32/1.05, -0.8 tracking.
      displayLarge: TextStyle(
        fontFamily: 'Nunito',
        fontWeight: FontWeight.w800,
        fontSize: 32,
        height: 1.05,
        letterSpacing: -0.8,
        color: ink,
      ),
      displayMedium: TextStyle(
        fontFamily: 'Nunito',
        fontWeight: FontWeight.w800,
        fontSize: 26,
        height: 1.1,
        letterSpacing: -0.6,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontFamily: 'Nunito',
        fontWeight: FontWeight.w700,
        fontSize: 19,
        height: 1.2,
        color: ink,
      ),
      titleMedium: const TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w600,
        fontSize: 16,
        height: 1.35,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w400,
        fontSize: 15,
        height: 1.35,
        color: ink,
      ),
      bodySmall: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w400,
        fontSize: 13,
        height: 1.35,
        color: muted,
      ),
      labelMedium: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w600,
        fontSize: 12,
        height: 1.3,
        color: muted,
      ),
      labelLarge: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w600,
        fontSize: 13,
        height: 1.3,
        color: ink,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      // Neutral grey focus border — never blue.
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: muted.withValues(alpha: 0.65), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: KeelTokens.overdue, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: KeelTokens.overdue, width: 1.5),
      ),
      hintStyle: TextStyle(color: muted, fontSize: 15),
      labelStyle: TextStyle(color: muted, fontSize: 13),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KeelTokens.radiusSheet),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KeelTokens.radiusCard),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ink,
      contentTextStyle: TextStyle(color: bg, fontSize: 14),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: card,
      headerBackgroundColor: accent,
      headerForegroundColor: Colors.white,
      dayForegroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? Colors.white : ink,
      ),
      dayBackgroundColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? accent : Colors.transparent,
      ),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: card,
      hourMinuteTextColor: ink,
      dialHandColor: accent,
      dialBackgroundColor: line,
    ),
    dividerColor: line,
    iconTheme: IconThemeData(color: ink, size: 24),
  );

  // Text scaling is applied once, at the app level in main.dart
  // (system scaler x in-app text-size setting).
  return base;
}

/// Greeting by time of day, as on Home.
String greetingFor(DateTime now) {
  final h = now.hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

String initialsOf(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

/// The first day of the week containing [date], given the user's
/// week-start setting ('monday' | 'saturday' | 'sunday'; anything else
/// means Monday). Pure function — see test/week_start_test.dart.
///
/// NOTE: Keel has no week-based grouping today — due-soon is a fixed
/// 2-day window (master prompt rule 8), Up next orders by due date,
/// and due labels only name the weekday. Nothing hard-coded a week
/// start, so there was nothing to rewire; this is the single place a
/// week boundary is computed, and it always reads the setting, ready
/// for the first week-based view.
DateTime startOfWeek(DateTime date, String weekStart) {
  final startWeekday = switch (weekStart) {
    'saturday' => DateTime.saturday,
    'sunday' => DateTime.sunday,
    _ => DateTime.monday,
  };
  final day = DateTime(date.year, date.month, date.day);
  final diff = (day.weekday - startWeekday + 7) % 7;
  return day.subtract(Duration(days: diff));
}

/// "Today" / "Tomorrow" / weekday / "Overdue" / date, for task due labels.
String dueLabel(DateTime? due, {required bool isDone}) {
  if (due == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(due.year, due.month, due.day);
  final diff = d.difference(today).inDays;
  if (isDone) return 'Done';
  if (diff < 0) return 'Overdue';
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff <= 6) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[d.weekday - 1];
  }
  return '${d.day}/${d.month}/${d.year}';
}
