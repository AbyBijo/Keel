import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// The single choke point for every haptic in the app.
///
/// All call sites go through here, so the Haptics toggle genuinely
/// silences everything when off, and the Vibration Intensity setting
/// (Light / Medium / Heavy, default Medium) applies everywhere.
///
/// Mapping (Flutter's HapticFeedback):
///   Light  -> lightImpact
///   Medium -> mediumImpact
///   Heavy  -> heavyImpact
///
/// Selection taps use the SAME mapping as impacts (not a separate
/// selectionClick): the user picked one strength for the whole app,
/// so tab taps must feel the same as every other tap. When haptics
/// is off, selection taps are silent too.
abstract final class KeelHaptics {
  static void _fire(WidgetRef ref) {
    final settings = ref.read(settingsProvider);
    if (!settings.hapticsOn) return;
    switch (settings.hapticStrength) {
      case 'light':
        HapticFeedback.lightImpact();
      case 'heavy':
        HapticFeedback.heavyImpact();
      default:
        HapticFeedback.mediumImpact();
    }
  }

  /// General press feedback (checkboxes, add button, …).
  static void impact(WidgetRef ref) => _fire(ref);

  /// Selection feedback (tab taps, …). Same strength as [impact].
  static void selection(WidgetRef ref) => _fire(ref);

  /// Preview buzz at exactly [strength] ('light' | 'medium' | 'heavy').
  /// Used by the Vibration Intensity control: tapping an option saves
  /// it and immediately plays it, so the user feels what they picked.
  /// Callers must only offer this while haptics is on (the control is
  /// disabled when off), but this also guards: no buzz when off.
  static void preview(WidgetRef ref, String strength) {
    final settings = ref.read(settingsProvider);
    if (!settings.hapticsOn) return;
    switch (strength) {
      case 'light':
        HapticFeedback.lightImpact();
      case 'heavy':
        HapticFeedback.heavyImpact();
      default:
        HapticFeedback.mediumImpact();
    }
  }
}
