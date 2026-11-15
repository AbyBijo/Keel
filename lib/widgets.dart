import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db.dart';
import 'haptics.dart';
import 'theme.dart';

// ---------------------------------------------------------------------------
// Card — radius 22, soft shadow in light mode only, none in dark.
// ---------------------------------------------------------------------------

class KeelCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;
  final String? semanticLabel;

  const KeelCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color,
    this.onTap,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? context.card,
        borderRadius: BorderRadius.circular(KeelTokens.radiusCard),
        boxShadow: context.isDark
            ? null
            : [
                const BoxShadow(
                  color: Color(0x140D1B26),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                  spreadRadius: -12,
                ),
                const BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 1,
                  offset: Offset(0, 1),
                ),
              ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: card,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chip — fully round, 14% tint fill, team colour text.
// ---------------------------------------------------------------------------

class KeelChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool selected;
  final Widget? leading;

  const KeelChip({
    super.key,
    required this.label,
    required this.color,
    this.onTap,
    this.selected = false,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? color
        : KeelTokens.tint14(color, context.card);
    final fg = selected ? Colors.white : color;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 4)],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return chip;
    return GestureDetector(onTap: onTap, child: chip);
  }
}

// ---------------------------------------------------------------------------
// Avatar — circle, 2.5px ring in first-team colour, 16% tint fill,
// initials in that colour; photo inside the same ring; no team = grey.
// ---------------------------------------------------------------------------

class PersonAvatar extends StatelessWidget {
  final Person person;
  final Color ringColor;
  final double size;
  final bool showPhoto;

  const PersonAvatar({
    super.key,
    required this.person,
    required this.ringColor,
    this.size = 44,
    this.showPhoto = true,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto =
        showPhoto && person.photoPath != null && person.photoPath!.isNotEmpty;
    final bg = KeelTokens.tint(ringColor, context.card);
    // Decode the photo at the size it is actually shown (× screen
    // density): a 1024px photo used to be fully decoded for every
    // 28–48px avatar in a list.
    final cachePx =
        (size * MediaQuery.of(context).devicePixelRatio).round();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        border: Border.all(color: ringColor, width: 2.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasPhoto
          ? Image.file(
              File(person.photoPath!),
              fit: BoxFit.cover,
              width: size,
              height: size,
              cacheWidth: cachePx,
              cacheHeight: cachePx,
              errorBuilder: (_, _, _) => _initials(context, ringColor),
            )
          : _initials(context, ringColor),
    );
  }

  Widget _initials(BuildContext context, Color color) {
    return Center(
      child: Text(
        initialsOf(person.name),
        style: TextStyle(
          fontFamily: 'Nunito',
          fontWeight: FontWeight.w800,
          fontSize: size * 0.36,
          color: color,
        ),
      ),
    );
  }
}

/// Overlapping stacked avatars, as on task cards and team cards.
class AvatarStack extends StatelessWidget {
  final List<({Person person, Color color})> members;
  final double size;

  const AvatarStack({super.key, required this.members, this.size = 28});

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) return const SizedBox.shrink();
    final shown = members.take(3).toList();
    return SizedBox(
      height: size,
      width: size + (shown.length - 1) * (size - 9),
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * (size - 9),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: context.card, width: 2),
                ),
                child: PersonAvatar(
                  person: shown[i].person,
                  ringColor: shown[i].color,
                  size: size - 4,
                ),
              ),
            ),
          if (members.length > 3)
            Positioned(
              left: 3 * (size - 9),
              child: Container(
                width: size - 4,
                height: size - 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.line,
                  border: Border.all(color: context.card, width: 2),
                ),
                child: Center(
                  child: Text(
                    '+${members.length - 3}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: context.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Checkbox — 9px squircle; fills green with a scale pop and a drawn check.
// ---------------------------------------------------------------------------

class KeelCheckbox extends ConsumerWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final double size;
  final String? semanticLabel;

  const KeelCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 26,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      checked: value,
      label: semanticLabel ?? (value ? 'Completed' : 'Mark complete'),
      child: GestureDetector(
        onTap: () {
          KeelHaptics.impact(ref);
          onChanged(!value);
        },
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: value ? 1.0 : 0.0),
              duration: KeelTokens.fade,
              curve: KeelTokens.easeOut,
              builder: (context, t, _) {
                final scale = 1.0 + 0.1 * math.sin(t * math.pi);
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: Color.lerp(
                        Colors.transparent,
                        KeelTokens.success,
                        t,
                      ),
                      borderRadius: BorderRadius.circular(KeelTokens.radiusCheck),
                      border: Border.all(
                        color: Color.lerp(
                          context.line,
                          KeelTokens.success,
                          t,
                        )!,
                        width: 2,
                      ),
                    ),
                    child: t > 0.4
                        ? Icon(
                            Icons.check_rounded,
                            size: size * 0.62,
                            color: Colors.white.withValues(alpha: t),
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Progress ring — dark dial, counts up, animates from the previous value.
// ---------------------------------------------------------------------------

class ProgressRing extends StatefulWidget {
  final double value; // 0..1
  final double size;
  final Color trackColor;
  final Color progressColor;
  final bool reduceMotion;

  const ProgressRing({
    super.key,
    required this.value,
    this.size = 116,
    this.trackColor = const Color(0x33FFFFFF),
    this.progressColor = const Color(0xFF4FD1C5),
    this.reduceMotion = false,
  });

  @override
  State<ProgressRing> createState() => _ProgressRingState();
}

class _ProgressRingState extends State<ProgressRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _curved;
  double _from = 0;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    // The arc eases in and out: gentle at both ends of the sweep,
    // instead of the previous constant-speed (linear) arc.
    // Curves.easeInOut (not easeInOutCubic): the cubic variant has
    // longer slow tails that would make the 700ms count-up feel
    // sluggish; easeInOut keeps the sweep symmetric and snappy.
    _curved = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
    _c.forward();
  }

  @override
  void didUpdateWidget(ProgressRing old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _from = old.value;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curved,
      builder: (context, _) {
        final v = widget.reduceMotion
            ? widget.value
            : _from + (widget.value - _from) * _curved.value;
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _RingPainter(
              value: v,
              trackColor: widget.trackColor,
              progressColor: widget.progressColor,
            ),
            child: Center(
              child: Text(
                '${(v * 100).round()}%',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w800,
                  fontSize: 30,
                  color: context.dialInk,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color trackColor;
  final Color progressColor;
  _RingPainter({
    required this.value,
    required this.trackColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);
    final progress = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      value.clamp(0, 1) * 2 * math.pi,
      false,
      progress,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.trackColor != trackColor ||
      old.progressColor != progressColor;
}

/// Thin progress bar (team cards, team page, sheets).
class ProgressBar extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  final Color? trackColor;
  final double height;

  const ProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.trackColor,
    this.height = 6,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Container(
        height: height,
        color: trackColor ?? context.line,
        child: Align(
          alignment: Alignment.centerLeft,
          // The old version wrapped the bar in an AnimatedContainer
          // with width: null, so the width never actually animated —
          // the bar jumped to its new value. TweenAnimationBuilder
          // animates the width factor from the previous value.
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: value.clamp(0, 1)),
            duration: KeelTokens.spring,
            curve: KeelTokens.easeOut,
            builder: (context, v, _) => FractionallySizedBox(
              widthFactor: v,
              child: Container(color: color),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Segmented control — sliding thumb.
// ---------------------------------------------------------------------------

class KeelSegmented<T> extends StatelessWidget {
  final List<(T value, String label)> options;
  final T selected;
  final ValueChanged<T> onChanged;

  const KeelSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final index = options.indexWhere((o) => o.$1 == selected);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: context.line,
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth / options.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: KeelTokens.spring,
                curve: KeelTokens.easeOut,
                left: math.max(0, index) * w,
                top: 0,
                bottom: 0,
                width: w,
                child: Container(
                  margin: const EdgeInsets.all(0),
                  decoration: BoxDecoration(
                    color: context.card,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: context.isDark
                        ? null
                        : [
                            const BoxShadow(
                              color: Color(0x140D1B26),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < options.length; i++)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => onChanged(options[i].$1),
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Text(
                            options[i].$2,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: i == index ? context.ink : context.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Buttons
// ---------------------------------------------------------------------------

class KeelButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color? background;
  final Color? foreground;
  final IconData? icon;
  final bool secondary;

  const KeelButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.background,
    this.foreground,
    this.icon,
    this.secondary = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = background ?? (secondary ? context.card : context.ink);
    final fg = foreground ?? (secondary ? context.ink : context.bg);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: context.line,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KeelTokens.radiusButton),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20),
              const SizedBox(width: 8),
            ],
            // Flexible + wrap: at 200% text scaling a long label must
            // wrap to two lines, never overflow the button.
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.visible,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------

class KeelTextField extends StatelessWidget {
  final TextEditingController controller;
  final String? label;
  final String? hint;
  final String? errorText;
  final TextInputType keyboardType;
  final TextCapitalization capitalization;
  final int maxLines;
  final bool autofocus;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final TextInputAction? textInputAction;

  const KeelTextField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.errorText,
    this.keyboardType = TextInputType.text,
    this.capitalization = TextCapitalization.sentences,
    this.maxLines = 1,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              label!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.muted,
              ),
            ),
          ),
        ],
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: capitalization,
          maxLines: maxLines,
          autofocus: autofocus,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          textInputAction: textInputAction,
          style: TextStyle(fontSize: 16, color: context.ink),
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state — illustration (icon in tinted circle) + one-tap action.
// ---------------------------------------------------------------------------

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KeelTokens.tint14(context.accent, context.card),
              ),
              child: Icon(icon, size: 34, color: context.accent),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.muted, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 20),
            KeelButton(label: actionLabel, onPressed: onAction),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header ("Up next" / "See all") and stat tile.
// ---------------------------------------------------------------------------

class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 19)),
          if (actionLabel != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                actionLabel!,
                style: TextStyle(
                  color: context.accent,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  final String value;
  final String label;
  final Color? valueColor;
  final VoidCallback? onTap;

  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.valueColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: KeelCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w800,
                fontSize: 22,
                color: valueColor ?? context.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: context.muted, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small square accent "+" button used in list-screen headers.
// ---------------------------------------------------------------------------

class KeelAddIconButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String tooltip;
  const KeelAddIconButton({super.key, required this.onPressed, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: context.accent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.add, color: Colors.white, size: 26),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom sheet helper — detents, drag handle, keyboard-aware.
// ---------------------------------------------------------------------------

Future<T?> showKeelSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext context, ScrollController scrollController)
  builder,
  bool large = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(KeelTokens.radiusSheet),
      ),
    ),
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: large ? 0.92 : 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 5,
            decoration: BoxDecoration(
              color: context.line,
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: builder(context, scrollController)),
        ],
      ),
    ),
  );
}

/// A simple (non-draggable) sheet for short content like the org switcher.
Future<T?> showKeelDialogSheet<T>(
  BuildContext context, {
  required Widget child,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(KeelTokens.radiusSheet),
      ),
    ),
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 5,
            decoration: BoxDecoration(
              color: context.line,
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(child: child),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
}
