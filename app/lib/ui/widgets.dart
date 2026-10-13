import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/activity.dart';
import 'theme.dart';

/// Runs [c] as an endless loop unless the user asked the OS to remove
/// animations (then it stays still). Call from didChangeDependencies.
void syncLoop(AnimationController c, BuildContext context, {bool reverse = false}) {
  if (MediaQuery.disableAnimationsOf(context)) {
    c.stop();
  } else if (!c.isAnimating) {
    c.repeat(reverse: reverse);
  }
}

/// Scales down slightly while pressed (the tactile feel of Bolt / Instagram
/// cards) and gives a light haptic tick on tap.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  const Pressable({super.key, required this.child, this.onTap, this.pressedScale = 0.97});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap != null && v != _down) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              },
        child: AnimatedScale(
          scale: _down ? widget.pressedScale : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}

/// Fades and slides its child in once, after [delay]. Used for staggered
/// entrances. Respects the system "remove animations" setting.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Offset from;
  const FadeSlideIn({super.key, required this.child, this.delay = Duration.zero, this.from = const Offset(0, 0.08)});

  /// Delay for the [i]-th item in a staggered list.
  static Duration stagger(int i) => Duration(milliseconds: 40 + 55 * i);

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return FadeTransition(
      opacity: _a,
      child: SlideTransition(position: Tween(begin: widget.from, end: Offset.zero).animate(_a), child: widget.child),
    );
  }
}

/// Rounded card. With [onTap] it becomes one accessible button whose label is
/// [semanticLabel] (or its text content), with a press animation.
class BentoCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;
  final Gradient? gradient;
  final double? radius;
  final bool outlined;

  const BentoCard({
    super.key,
    required this.child,
    this.color,
    this.onTap,
    this.padding = const EdgeInsets.all(20),
    this.semanticLabel,
    this.gradient,
    this.radius,
    this.outlined = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final r = BorderRadius.circular(radius ?? t.radius);
    final plain = color == null && gradient == null;
    final card = Container(
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? t.card) : null,
        gradient: gradient,
        borderRadius: r,
        border: t.borderWidth > 0
            ? Border.all(color: Colors.white, width: t.borderWidth)
            : (plain && outlined && context.isDark ? Border.all(color: t.line) : null),
        boxShadow: plain ? t.elevation : null,
      ),
      // Transparent Material so ripples of rows/switches inside the card stay visible.
      child: Material(
        type: MaterialType.transparency,
        borderRadius: r,
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
    if (onTap == null) return card;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: Pressable(onTap: onTap, child: card),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionTitle(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 28, 0, 12),
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

/// Rounded-square coloured icon, as in WhatsApp / iOS settings rows.
class SquircleIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const SquircleIcon(this.icon, this.color, {super.key, this.size = 38});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(color, Colors.white, 0.15)!, color],
          ),
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: Icon(icon, size: size * 0.55, color: Colors.white),
      );
}

/// Instagram-story style gradient ring around a circular child. [seen] greys it out.
class GradientRing extends StatelessWidget {
  final Widget child;
  final double size;
  final bool seen;
  final List<Color>? colors;
  const GradientRing({super.key, required this.child, this.size = 68, this.seen = false, this.colors});

  @override
  Widget build(BuildContext context) {
    final a = context.colors.primary, b = context.colors.secondary;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: seen
            ? null
            : SweepGradient(colors: colors ?? [a, b, const Color(0xFFFF4D8D), a]),
        color: seen ? context.tokens.line : null,
      ),
      child: Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(shape: BoxShape.circle, color: context.tokens.canvas),
        child: ClipOval(child: child),
      ),
    );
  }
}

/// Slowly drifting colour blobs behind content (onboarding, sign-in, hero cards).
class AuroraBackground extends StatefulWidget {
  final List<Color> colors;
  final Widget? child;
  final double intensity;
  const AuroraBackground({super.key, required this.colors, this.child, this.intensity = 0.55});

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 14));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncLoop(_c, context);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    // Sized by the child (cards) or by the parent when there is no child (backdrops).
    return Stack(children: [
      Positioned.fill(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              painter: _AuroraPainter(widget.colors, still ? 0.2 : _c.value, widget.intensity),
            ),
          ),
        ),
      ),
      widget.child ?? const SizedBox.expand(),
    ]);
  }
}

class _AuroraPainter extends CustomPainter {
  final List<Color> colors;
  final double t, intensity;
  _AuroraPainter(this.colors, this.t, this.intensity);

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < colors.length; i++) {
      final phase = t * 2 * math.pi + i * 2.1;
      final c = Offset(
        size.width * (0.5 + 0.38 * math.cos(phase + i)),
        size.height * (0.35 + 0.3 * math.sin(phase * 0.8 + i * 1.3)),
      );
      final r = size.shortestSide * (0.55 + 0.1 * math.sin(phase));
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [
            colors[i].withValues(alpha: intensity),
            colors[i].withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.t != t;
}

/// Animated confidence ring (0..1) with a big centred label.
class ConfidenceRing extends StatelessWidget {
  final double value;
  final double size;
  final Color? color;
  final Color? track;
  final Widget? center;
  const ConfidenceRing({super.key, required this.value, this.size = 120, this.color, this.track, this.center});

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
          painter: _RingPainter(v, c, track ?? context.tokens.cardHigh),
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
  final double tint;
  const GlassPanel(
      {super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 24, this.tint = 0.4});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: tint),
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
  if (d.inSeconds < 60) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  if (d.inDays < 7) return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][t.weekday - 1];
  return '${t.day}/${t.month}/${t.year % 100}';
}

/// WhatsApp-style day header: Today, Yesterday, weekday, or date.
String dayLabel(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7) {
    return const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][t.weekday - 1];
  }
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${t.day} ${months[t.month - 1]} ${t.year}';
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
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          decoration: BoxDecoration(
            color: context.tokens.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: c.withValues(alpha: 0.6), width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 30, offset: const Offset(0, 12))],
          ),
          child: Row(children: [
            IconBadge(activityIcon(event.kind, event.severity), background: c, foreground: Colors.black, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(event.title, style: context.text.titleMedium),
                if (event.detail.isNotEmpty)
                  Text(event.detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium?.copyWith(color: context.tokens.muted)),
              ]),
            ),
            IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded), tooltip: 'Dismiss'),
          ]),
        ),
      ),
    );
  }
}
