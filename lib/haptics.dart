import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibration/vibration.dart';

import 'providers.dart';

/// The single choke point for every haptic in the app.
///
/// All call sites go through here, so the Haptics toggle genuinely
/// silences everything when off, and the Vibration Intensity setting
/// (Light / Medium / Heavy, default Medium) applies everywhere.
///
/// Mapping (direct motor control via the `vibration` package):
///   Light  -> 15 ms, amplitude 64  (soft tick)
///   Medium -> 30 ms, amplitude 128
///   Heavy  -> 60 ms, amplitude 255 (strong buzz)
///
/// Flutter's `HapticFeedback` is NOT used: on Android it is a polite
/// request to the system, silently ignored when the phone's
/// touch-vibration setting is off — no error, no buzz, and the app
/// never knows. Driving the motor directly does not depend on that
/// toggle. On devices without amplitude control the duration still
/// applies; on devices with no vibrator at all the call is a no-op.
///
/// Selection taps use the SAME mapping as impacts (not a separate
/// selectionClick): the user picked one strength for the whole app,
/// so tab taps must feel the same as every other tap. When haptics
/// is off, selection taps are silent too.
///
/// Every platform call is wrapped in try/catch: in widget tests
/// there is no platform channel (MissingPluginException), and a
/// missing vibrator must never crash a tap.
abstract final class KeelHaptics {
  static const _strengths = <String, ({int durationMs, int amplitude})>{
    'light': (durationMs: 15, amplitude: 64),
    'medium': (durationMs: 30, amplitude: 128),
    'heavy': (durationMs: 60, amplitude: 255),
  };

  static void _fire(WidgetRef ref) {
    final settings = ref.read(settingsProvider);
    if (!settings.hapticsOn) return;
    _buzz(_strengths[settings.hapticStrength] ?? _strengths['medium']!);
  }

  static void _buzz(({int durationMs, int amplitude}) strength) {
    unawaited(
      Vibration.vibrate(
        duration: strength.durationMs,
        amplitude: strength.amplitude,
      ).catchError((_) {}),
    );
  }

  /// General press feedback (checkboxes, add button, saves, deletes, …).
  static void impact(WidgetRef ref) => _fire(ref);

  /// Selection feedback (tab taps, …). Same strength as [impact].
  static void selection(WidgetRef ref) => _fire(ref);

  /// Preview buzz at exactly [strength] ('light' | 'medium' | 'heavy').
  /// Used by the Vibration Intensity control and the "Test vibration"
  /// button: tapping saves it and immediately plays it, so the user
  /// feels what they picked. Callers must only offer this while
  /// haptics is on (the controls are disabled when off), but this
  /// also guards: no buzz when off.
  static void preview(WidgetRef ref, String strength) {
    final settings = ref.read(settingsProvider);
    if (!settings.hapticsOn) return;
    _buzz(_strengths[strength] ?? _strengths['medium']!);
  }

  /// Buzz at the currently saved strength, for the "Test vibration"
  /// button in Settings.
  static void test(WidgetRef ref) => _fire(ref);
}
