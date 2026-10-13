import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/currency.dart';
import '../ml/authenticity_checker.dart';
import '../ml/object_detector.dart';
import '../scan_controller.dart';
import 'theme.dart';
import 'widgets.dart';

/// Full-screen scanner in TikTok's layout: text tabs on top, an action rail on
/// the right, and the result as a bold caption over a bottom gradient.
class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scan = AppScope.of(context).scan;
    return ListenableBuilder(
      listenable: scan,
      builder: (context, _) {
        final money = scan.mode == ScanMode.currency;
        final locked = scan.lastNote != null && scan.status == scan.lastNote?.spoken;
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(fit: StackFit.expand, children: [
            _Preview(scan: scan),
            // Scrims keep white text readable on any scene.
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, 0.18, 0.55, 1],
                    colors: [Color(0x99000000), Color(0x00000000), Color(0x00000000), Color(0xDD000000)],
                  ),
                ),
              ),
            ),
            if (money) _Reticle(locked: locked, scanning: scan.hasCurrencyModel && !locked),
            SafeArea(
              bottom: false,
              child: Column(children: [
                const SizedBox(height: 6),
                _ModeTabs(scan: scan),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: scan.hint == null
                      ? const SizedBox(height: 0)
                      : Padding(
                          key: ValueKey(scan.hint),
                          padding: const EdgeInsets.only(top: 10),
                          child: GlassPanel(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            radius: 20,
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.info_outline_rounded, color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                              Text(scan.hint!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ),
                ),
              ]),
            ),
            Positioned(right: 10, bottom: 104, child: _ActionRail(scan: scan)),
            Positioned(left: 18, right: 92, bottom: 100, child: _Caption(scan: scan)),
            if (scan.authPhase != AuthPhase.idle) _AuthSheet(scan: scan),
          ]),
        );
      },
    );
  }
}

class _Preview extends StatelessWidget {
  final ScanController scan;
  const _Preview({required this.scan});

  @override
  Widget build(BuildContext context) {
    final c = scan.camera;
    if (c == null || !c.value.isInitialized) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(strokeWidth: 3, color: context.colors.primary),
          ),
          const SizedBox(height: 16),
          Text(scan.status, style: const TextStyle(color: Colors.white70)),
        ]),
      );
    }
    final size = c.value.previewSize;
    final w = size?.height ?? 1, h = size?.width ?? 1; // portrait
    return Semantics(
      label: 'Camera view. Double tap to repeat the last result.',
      button: true,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => scan.announcer.say(scan.status, dedupe: Duration.zero, force: true),
        child: ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: w,
              height: h,
              child: Stack(fit: StackFit.expand, children: [
                CameraPreview(c),
                if (scan.mode == ScanMode.scene)
                  CustomPaint(painter: _BoxesPainter(scan.detections, context.colors.primary)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _BoxesPainter extends CustomPainter {
  final List<Detection> dets;
  final Color color;
  _BoxesPainter(this.dets, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.007
      ..strokeCap = StrokeCap.round
      ..color = color;
    for (final d in dets.take(6)) {
      final r = Rect.fromLTRB(d.left * size.width, d.top * size.height, d.right * size.width, d.bottom * size.height);
      // Corner brackets rather than a full box: lighter over the scene.
      final l = (r.shortestSide * 0.22).clamp(s * 0.03, s * 0.09);
      for (final (x, y, dx, dy) in [
        (r.left, r.top, 1.0, 1.0),
        (r.right, r.top, -1.0, 1.0),
        (r.left, r.bottom, 1.0, -1.0),
        (r.right, r.bottom, -1.0, -1.0),
      ]) {
        canvas.drawPath(
          Path()
            ..moveTo(x, y + dy * l)
            ..lineTo(x, y)
            ..lineTo(x + dx * l, y),
          stroke,
        );
      }
      final tp = TextPainter(
        text: TextSpan(
          text: '${d.label}  ${(d.score * 100).round()}%',
          style: TextStyle(color: Colors.black, fontSize: s * 0.034, fontWeight: FontWeight.w700, fontFamily: 'Inter'),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final pad = s * 0.018;
      final chip = RRect.fromRectAndRadius(
        Rect.fromLTWH(r.left, (r.top - tp.height - pad * 2 - s * 0.01).clamp(0, size.height), tp.width + pad * 2,
            tp.height + pad * 1.2),
        Radius.circular(s * 0.03),
      );
      canvas.drawRRect(chip, Paint()..color = color);
      tp.paint(canvas, Offset(chip.left + pad, chip.top + pad * 0.6));
    }
  }

  @override
  bool shouldRepaint(_BoxesPainter old) => old.dets != dets;
}

/// Note-shaped frame with a sweeping scan line; turns accent when locked.
class _Reticle extends StatefulWidget {
  final bool locked;
  final bool scanning;
  const _Reticle({required this.locked, required this.scanning});

  @override
  State<_Reticle> createState() => _ReticleState();
}

class _ReticleState extends State<_Reticle> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncLoop(_c, context, reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width * 0.84;
    final h = w * 0.56;
    final color = widget.locked ? context.colors.primary : Colors.white;
    return IgnorePointer(
      child: Center(
        child: AnimatedScale(
          scale: widget.locked ? 1.04 : 1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _CornersPainter(color))),
              if (widget.scanning && !MediaQuery.disableAnimationsOf(context))
                AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) => Positioned(
                    left: 14,
                    right: 14,
                    top: 10 + (h - 20) * Curves.easeInOut.transform(_c.value),
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: LinearGradient(colors: [
                          context.colors.primary.withValues(alpha: 0),
                          context.colors.primary,
                          context.colors.primary.withValues(alpha: 0),
                        ]),
                        boxShadow: [BoxShadow(color: context.colors.primary.withValues(alpha: 0.7), blurRadius: 16)],
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _CornersPainter extends CustomPainter {
  final Color color;
  _CornersPainter(this.color);

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const l = 40.0, r = 24.0;
    for (final (x, y, dx, dy) in [
      (0.0, 0.0, 1.0, 1.0),
      (s.width, 0.0, -1.0, 1.0),
      (0.0, s.height, 1.0, -1.0),
      (s.width, s.height, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(x, y + dy * l)
          ..lineTo(x, y + dy * r)
          ..quadraticBezierTo(x, y, x + dx * r, y)
          ..lineTo(x + dx * l, y),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_CornersPainter old) => old.color != color;
}

/// TikTok "Following | For You" style text tabs with an underline indicator.
class _ModeTabs extends StatelessWidget {
  final ScanController scan;
  const _ModeTabs({required this.scan});

  @override
  Widget build(BuildContext context) {
    Widget tab(ScanMode m, String label) {
      final sel = scan.mode == m;
      return Semantics(
        selected: sel,
        button: true,
        label: '$label mode',
        excludeSemantics: true,
        child: Pressable(
          onTap: () => scan.setMode(m),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: sel ? 19 : 17,
                  fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                  color: sel ? Colors.white : Colors.white60,
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 8)],
                ),
                child: Text(label),
              ),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                width: sel ? 28 : 0,
                height: 3,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
              ),
            ]),
          ),
        ),
      );
    }

    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      tab(ScanMode.currency, 'Money'),
      Container(width: 1, height: 16, color: Colors.white38),
      tab(ScanMode.scene, 'Objects'),
    ]);
  }
}

/// Vertical action buttons on the right edge, as in TikTok.
class _ActionRail extends StatelessWidget {
  final ScanController scan;
  const _ActionRail({required this.scan});

  @override
  Widget build(BuildContext context) {
    final money = scan.mode == ScanMode.currency;
    final hasNote = scan.lastNote != null;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _RailButton(
        icon: scan.torchOn ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
        label: scan.torchOn ? 'Light on' : 'Light',
        active: scan.torchOn,
        onTap: scan.toggleTorch,
      ),
      _RailButton(
        icon: Icons.replay_rounded,
        label: 'Repeat',
        onTap: () => scan.announcer.say(scan.status, dedupe: Duration.zero, force: true),
      ),
      if (money) ...[
        _RailButton(
          icon: Icons.verified_user_rounded,
          label: 'Check fake',
          enabled: hasNote && !scan.authRunning,
          onTap: scan.checkAuthenticity,
        ),
        _RailButton(
          icon: Icons.add_rounded,
          label: 'Add',
          enabled: hasNote,
          highlight: true,
          onTap: scan.addToTotal,
        ),
      ],
    ]);
  }
}

class _RailButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool active;
  final bool highlight;
  const _RailButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.active = false,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.primary;
    final filled = (highlight && enabled) || active;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Pressable(
          onTap: enabled ? onTap : null,
          pressedScale: 0.85,
          child: AnimatedOpacity(
            opacity: enabled ? 1 : 0.4,
            duration: const Duration(milliseconds: 200),
            child: Column(children: [
              filled
                  ? Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                      child: Icon(icon, color: context.colors.onPrimary, size: 26),
                    )
                  : GlassPanel(
                      padding: const EdgeInsets.all(13),
                      radius: 26,
                      tint: 0.3,
                      child: Icon(icon, color: Colors.white, size: 26),
                    ),
              const SizedBox(height: 4),
              Text(label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                    shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                  )),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Bottom-left caption: the amount big, the spoken status under it.
class _Caption extends StatelessWidget {
  final ScanController scan;
  const _Caption({required this.scan});

  static const _shadow = [Shadow(color: Colors.black87, blurRadius: 12)];

  @override
  Widget build(BuildContext context) {
    final money = scan.mode == ScanMode.currency;
    final note = scan.lastNote;
    final showNote = money && note != null && scan.status == note.spoken;

    if (money && scan.modelsLoaded && !scan.hasCurrencyModel) return const _ModelMissing();

    return Semantics(
      liveRegion: true,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(position: Tween(begin: const Offset(0, .25), end: Offset.zero).animate(a), child: c),
        ),
        child: Column(
          key: ValueKey('${scan.mode}${scan.status}'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showNote) ...[
              Row(children: [
                Text(currencyInfo(note.currency)?.flag ?? '', style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Text(currencyName(note.currency),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, shadows: _shadow)),
              ]),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(formatAmount(note.currency, note.value),
                    style: context.text.displayMedium?.copyWith(color: Colors.white, shadows: _shadow)),
              ),
            ] else
              Text(scan.status,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.headlineSmall?.copyWith(color: Colors.white, shadows: _shadow)),
            const SizedBox(height: 10),
            if (money)
              _ConfidenceBar(value: scan.lastConfidence)
            else
              _SceneTags(scan: scan),
          ],
        ),
      ),
    );
  }
}

class _ConfidenceBar extends StatelessWidget {
  final double value;
  const _ConfidenceBar({required this.value});

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: value.clamp(0, 1).toDouble()),
              duration: const Duration(milliseconds: 400),
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                backgroundColor: Colors.white24,
                color: context.colors.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text('${(value * 100).round()}% sure',
            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13)),
      ]);
}

/// Instagram-style tags for what was found, plus the scene classifier's guess.
class _SceneTags extends StatelessWidget {
  final ScanController scan;
  const _SceneTags({required this.scan});

  @override
  Widget build(BuildContext context) {
    final labels = <String>{for (final d in scan.detections) d.label};
    final guess = scan.sceneGuess;
    if (labels.isEmpty && guess == null) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final l in labels.take(5)) _tag(context, Icons.label_rounded, l, filled: true),
      if (guess != null && !labels.contains(guess))
        _tag(context, Icons.auto_awesome_rounded, '$guess ${(scan.sceneGuessScore * 100).round()}%'),
    ]);
  }

  Widget _tag(BuildContext context, IconData icon, String text, {bool filled = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: filled ? context.colors.primary : Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: filled ? context.colors.onPrimary : Colors.white),
          const SizedBox(width: 5),
          Text(text,
              style: TextStyle(
                  color: filled ? context.colors.onPrimary : Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      );
}

class _ModelMissing extends StatelessWidget {
  const _ModelMissing();

  @override
  Widget build(BuildContext context) => GlassPanel(
        radius: 24,
        padding: const EdgeInsets.all(16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_rounded, color: context.colors.primary),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Money recognition is not installed in this build yet. Objects mode and the manual counterfeit checks '
              'work now.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, height: 1.35),
            ),
          ),
        ]),
      );
}

/// Step-by-step counterfeit screening, then the verdict, as a Bolt-style bottom sheet.
class _AuthSheet extends StatelessWidget {
  final ScanController scan;
  const _AuthSheet({required this.scan});

  @override
  Widget build(BuildContext context) {
    final done = scan.authPhase == AuthPhase.done;
    final note = scan.authNote;
    final t = context.tokens;
    final (Color c, IconData icon, String title) = switch (scan.verdict) {
      Verdict.noSignsOfCounterfeit => (t.success, Icons.verified_rounded, 'No counterfeit signs'),
      Verdict.possibleCounterfeit => (t.danger, Icons.gpp_bad_rounded, 'Possible counterfeit'),
      Verdict.uncertain => (t.warning, Icons.help_rounded, 'Inconclusive, try again'),
      Verdict.unavailable => (context.colors.primary, Icons.touch_app_rounded, 'Check by hand'),
      null => (context.colors.primary, Icons.hourglass_top_rounded, 'Checking…'),
    };
    final checks = note == null ? const <String>[] : scan.authenticity?.checksFor(note.currency) ?? const [];
    return Stack(children: [
      Positioned.fill(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          color: Colors.black.withValues(alpha: done ? 0.6 : 0.25),
        ),
      ),
      Align(
        alignment: Alignment.bottomCenter,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 1, end: 0),
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
          builder: (context, v, child) => FractionalTranslation(translation: Offset(0, v), child: child),
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 96),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(color: t.line, borderRadius: BorderRadius.circular(3)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(18)),
                      child: Icon(icon, color: Colors.black, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Semantics(liveRegion: true, child: Text(title, style: context.text.titleLarge)),
                        if (note != null)
                          Text(formatAmount(note.currency, note.value),
                              style: context.text.bodyLarge?.copyWith(color: t.muted)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  for (var i = 0; i < scan.authSteps.length; i++) _stepRow(context, i),
                  if (!done && scan.authSteps.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: t.cardHigh, borderRadius: BorderRadius.circular(20)),
                      child: Text(
                          AuthenticityChecker.instruction(
                              scan.authSteps[scan.authStepIndex.clamp(0, scan.authSteps.length - 1)]),
                          style: context.text.titleMedium),
                    ),
                  ],
                  if (done && (scan.verdict == Verdict.unavailable || scan.verdict == Verdict.possibleCounterfeit)) ...[
                    const SizedBox(height: 4),
                    for (var k = 0; k < checks.length; k++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: context.colors.primary, shape: BoxShape.circle),
                            child: Text('${k + 1}',
                                style: context.text.labelMedium?.copyWith(
                                    color: context.colors.onPrimary, fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(checks[k], style: context.text.bodyLarge)),
                        ]),
                      ),
                  ],
                  if (done) ...[
                    const SizedBox(height: 12),
                    Text('This is a screening aid, not a guarantee. When in doubt, ask a bank.',
                        style: context.text.bodySmall?.copyWith(color: t.muted)),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(onPressed: scan.dismissAuthResult, child: const Text('Done')),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _stepRow(BuildContext context, int i) {
    final step = scan.authSteps[i];
    final result = i < scan.authResults.length ? scan.authResults[i] : null;
    final active = i == scan.authStepIndex && scan.authPhase != AuthPhase.done;
    final t = context.tokens;
    final Widget leading = result != null
        ? Icon(result.failed ? Icons.cancel_rounded : result.clearlyPassed ? Icons.check_circle_rounded : Icons.help_rounded,
            color: result.failed ? t.danger : result.clearlyPassed ? t.success : t.warning)
        : active
            ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: context.colors.primary))
            : Icon(Icons.radio_button_unchecked_rounded, color: t.muted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        SizedBox(width: 28, child: Center(child: leading)),
        const SizedBox(width: 12),
        Expanded(child: Text(AuthenticityChecker.stepName(step), style: context.text.titleMedium)),
        if (active)
          Text(switch (scan.authPhase) {
            AuthPhase.capturing => 'Capturing',
            AuthPhase.analysing => 'Analysing',
            _ => 'Get ready',
          }, style: context.text.bodyMedium?.copyWith(color: t.muted)),
      ]),
    );
  }
}
