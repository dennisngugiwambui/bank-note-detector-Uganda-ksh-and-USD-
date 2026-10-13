import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/activity.dart';
import 'theme.dart';

/// Rounded bento tile. With [onTap] it becomes one accessible button whose
/// label is [semanticLabel] (or its text content).
class BentoCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;
  final Gradient? gradient;

  const BentoCard({
    super.key,
    required this.child,
    this.color,
    this.onTap,
    this.padding = const EdgeInsets.all(20),
    this.semanticLabel,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final radius = BorderRadius.circular(t.radius);
    final card = Ink(
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? t.card) : null,
        gradient: gradient,
        borderRadius: radius,
        border: t.borderWidth > 0 ? Border.all(color: Colors.white, width: t.borderWidth) : null,
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return Material(type: MaterialType.transparency, child: card);
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(borderRadius: radius, onTap: onTap, child: card),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionTitle(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
        child: Row(children: [
          Expanded(child: Semantics(header: true, child: Text(title, style: context.text.titleLarge))),
          ?trailing,
        ]),
      );
}

/// Round icon badge used across tiles.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color? background;
  final Color? foreground;
  final double size;
  const IconBadge(this.icon, {super.key, this.background, this.foreground, this.size = 48});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: background ?? context.tokens.cardHigh, shape: BoxShape.circle),
        child: Icon(icon, size: size * 0.5, color: foreground ?? context.colors.onSurface),
      );
}

/// Animated confidence ring (0..1) with a big centred label.
class ConfidenceRing extends StatelessWidget {
  final double value;
  final double size;
  final Color? color;
  final Widget? center;
  const ConfidenceRing({super.key, required this.value, this.size = 120, this.color, this.center});

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.primary;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0, 1).toDouble()),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(v, c, context.tokens.cardHigh),
          child: Center(
            child: center ?? Text('${(v * 100).round()}%', style: context.text.headlineMedium),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color color, track;
  _RingPainter(this.v, this.color, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.09;
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, math.pi * 2, false, p..color = track);
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * v, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.v != v || old.color != color;
}

/// Frosted panel for overlays on the camera preview.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  const GlassPanel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 24});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: child,
          ),
        ),
      );
}

Color severityColor(BuildContext context, Severity s) => switch (s) {
      Severity.info => context.colors.primary,
      Severity.success => context.tokens.success,
      Severity.warning => context.tokens.warning,
      Severity.danger => context.tokens.danger,
    };

IconData activityIcon(ActivityKind k, Severity s) => switch (k) {
      ActivityKind.note => Icons.payments_rounded,
      ActivityKind.authenticity => s == Severity.danger ? Icons.gpp_bad_rounded : Icons.verified_user_rounded,
      ActivityKind.obstacle => Icons.warning_amber_rounded,
      ActivityKind.system => Icons.info_rounded,
    };

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${t.day}/${t.month}/${t.year}';
}

/// Heads-up banner that slides in from the top for alerts.
class AlertBanner extends StatelessWidget {
  final ActivityEvent event;
  final VoidCallback onClose;
  const AlertBanner({super.key, required this.event, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final c = severityColor(context, event.severity);
    return Semantics(
      liveRegion: true,
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          decoration: BoxDecoration(
            color: context.tokens.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: c, width: 2),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: Row(children: [
            IconBadge(activityIcon(event.kind, event.severity), background: c, foreground: Colors.black, size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(event.title, style: context.text.titleMedium),
                if (event.detail.isNotEmpty)
                  Text(event.detail, style: context.text.bodyMedium?.copyWith(color: context.tokens.muted)),
              ]),
            ),
            IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded), tooltip: 'Dismiss'),
          ]),
        ),
      ),
    );
  }
}
