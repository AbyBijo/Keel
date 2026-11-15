import 'package:flutter_test/flutter_test.dart';
import 'package:keel/theme.dart';

/// Tests for startOfWeek (lib/theme.dart) — the single place a week
/// boundary is computed, driven by the Settings → Personalisation
/// "Week starts on" setting (Monday / Saturday / Sunday, default
/// Monday). Anchor date: Sunday 2026-11-15.
void main() {
  group('startOfWeek', () {
    test('Monday start: a Sunday belongs to the previous Monday week', () {
      expect(startOfWeek(DateTime(2026, 11, 15), 'monday'),
          DateTime(2026, 11, 9));
    });

    test('Sunday start: a Sunday is its own week start', () {
      expect(startOfWeek(DateTime(2026, 11, 15), 'sunday'),
          DateTime(2026, 11, 15));
    });

    test('Saturday start: a Sunday belongs to the Saturday week', () {
      expect(startOfWeek(DateTime(2026, 11, 15), 'saturday'),
          DateTime(2026, 11, 14));
    });

    test('a date already on the start day returns itself', () {
      expect(startOfWeek(DateTime(2026, 11, 9), 'monday'),
          DateTime(2026, 11, 9));
      expect(startOfWeek(DateTime(2026, 11, 14), 'saturday'),
          DateTime(2026, 11, 14));
    });

    test('mid-week date with a Monday start', () {
      expect(startOfWeek(DateTime(2026, 11, 12), 'monday'),
          DateTime(2026, 11, 9));
    });

    test('an unknown value falls back to Monday', () {
      expect(startOfWeek(DateTime(2026, 11, 15), 'tuesday'),
          DateTime(2026, 11, 9));
    });
  });
}
