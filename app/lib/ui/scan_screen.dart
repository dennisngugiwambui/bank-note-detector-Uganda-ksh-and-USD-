import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/currency.dart';
import '../ml/authenticity_checker.dart';
import '../ml/object_detector.dart';
import '../scan_controller.dart';
import 'theme.dart';
import 'widgets.dart';

class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scan = AppScope.of(context).scan;
    return ListenableBuilder(
      listenable: scan,
      builder: (context, _) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(fit: StackFit.expand, children: [
          _Preview(scan: scan),
          if (scan.mode == ScanMode.currency) _Reticle(locked: scan.lastNote != null && scan.status == scan.lastNote?.spoken),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(children: [
                _TopBar(scan: scan),
                if (scan.hint != null) ...[
                  const SizedBox(height: 10),
                  GlassPanel(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    radius: 18,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.info_outline_rounded, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text(scan.hint!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ],
              ]),
            ),
          ),
          Positioned(left: 12, right: 12, bottom: 100, child: _ResultPanel(scan: scan)),
          if (scan.authPhase != AuthPhase.idle) _AuthOverlay(scan: scan),
        ]),
      ),
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
          const CircularProgressIndicator(color: Colors.white),
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
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.008
      ..color = color;
    for (final d in dets.take(6)) {
      final r = RRect.fromRectAndRadius(
        Rect.fromLTRB(d.left * size.width, d.top * size.height, d.right * size.width, d.bottom * size.height),
        Radius.circular(size.width * 0.03),
      );
      canvas.drawRRect(r, stroke);
      final tp = TextPainter(
        text: TextSpan(
          text: ' ${d.label} ${(d.score * 100).round()}% ',
          style: TextStyle(
              color: Colors.black, backgroundColor: color, fontSize: size.width * 0.035, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(r.left, (r.top - tp.height).clamp(0, size.height)));
    }
  }

  @override
  bool shouldRepaint(_BoxesPainter old) => old.dets != dets;
}

/// Corner-bracket framing guide; turns to the accent colour on a confident read.
class _Reticle extends StatelessWidget {
  final bool locked;
  const _Reticle({required this.locked});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Center(
          child: AnimatedScale(
            scale: locked ? 1.04 : 1,
            duration: const Duration(milliseconds: 300),
            child: SizedBox(
              width: MediaQuery.sizeOf(context).width * 0.82,
              height: MediaQuery.sizeOf(context).width * 0.48,
              child: CustomPaint(painter: _CornersPainter(locked ? context.colors.primary : Colors.white)),
            ),
          ),
        ),
      );
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
    const l = 36.0, r = 22.0;
    for (final (x, y, dx, dy) in [(0.0, 0.0, 1.0, 1.0), (s.width, 0.0, -1.0, 1.0), (0.0, s.height, 1.0, -1.0), (s.width, s.height, -1.0, -1.0)]) {
      final path = Path()
        ..moveTo(x, y + dy * l)
        ..lineTo(x, y + dy * r)
        ..quadraticBezierTo(x, y, x + dx * r, y)
        ..lineTo(x + dx * l, y);
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_CornersPainter old) => old.color != color;
}

class _TopBar extends StatelessWidget {
  final ScanController scan;
  const _TopBar({required this.scan});

  @override
  Widget build(BuildContext context) {
    Widget seg(ScanMode m, IconData icon, String label) {
      final sel = scan.mode == m;
      return Expanded(
        child: Semantics(
          selected: sel,
          button: true,
          label: '$label mode',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: () => scan.setMode(m),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 48,
              decoration: BoxDecoration(
                color: sel ? context.colors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 20, color: sel ? context.colors.onPrimary : Colors.white),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        color: sel ? context.colors.onPrimary : Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              ]),
            ),
          ),
        ),
      );
    }

    return Row(children: [
      Expanded(
        child: GlassPanel(
          padding: const EdgeInsets.all(5),
          radius: 30,
          child: Row(children: [
            seg(ScanMode.currency, Icons.payments_rounded, 'Money'),
            seg(ScanMode.scene, Icons.visibility_rounded, 'Objects'),
          ]),
        ),
      ),
      const SizedBox(width: 10),
      GlassPanel(
        padding: EdgeInsets.zero,
        radius: 30,
        child: IconButton(
          iconSize: 26,
          padding: const EdgeInsets.all(13),
          tooltip: scan.torchOn ? 'Turn light off' : 'Turn light on',
          onPressed: scan.toggleTorch,
          icon: Icon(scan.torchOn ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
              color: scan.torchOn ? context.colors.primary : Colors.white),
        ),
      ),
    ]);
  }
}

class _ResultPanel extends StatelessWidget {
  final ScanController scan;
  const _ResultPanel({required this.scan});

  @override
  Widget build(BuildContext context) {
    final note = scan.lastNote;
    final currency = scan.mode == ScanMode.currency;
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      radius: 28,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (currency)
            ConfidenceRing(
              value: scan.lastConfidence,
              size: 72,
              center: Text(
                note != null ? (currencyInfo(note.currency)?.flag ?? '') : '${(scan.lastConfidence * 100).round()}',
                style: const TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.w800),
              ),
            ),
          if (currency) const SizedBox(width: 16),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (c, a) => FadeTransition(
                    opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, .2), end: Offset.zero).animate(a), child: c)),
                child: Column(
                  key: ValueKey(scan.status),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (currency && note != null && scan.status == note.spoken)
                      Text(formatAmount(note.currency, note.value),
                          style: context.text.headlineMedium?.copyWith(color: Colors.white)),
                    Text(scan.status,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: (currency && note != null && scan.status == note.spoken
                                ? context.text.bodyLarge?.copyWith(color: Colors.white70)
                                : context.text.titleLarge?.copyWith(color: Colors.white))),
                  ],
                ),
              ),
            ),
          ),
        ]),
        if (currency) ...[
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: note == null || scan.authRunning ? null : scan.checkAuthenticity,
                icon: const Icon(Icons.verified_user_rounded),
                label: const Text('Check fake'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                onPressed: note == null ? null : scan.addToTotal,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add'),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}

/// Step-by-step counterfeit screening overlay, then the verdict card.
class _AuthOverlay extends StatelessWidget {
  final ScanController scan;
  const _AuthOverlay({required this.scan});

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
    return Container(
      color: Colors.black.withValues(alpha: done ? 0.75 : 0.35),
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
      child: Material(
        color: t.card,
        borderRadius: BorderRadius.circular(32),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconBadge(icon, background: c, foreground: Colors.black, size: 52),
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
              const SizedBox(height: 8),
              Text(AuthenticityChecker.instruction(scan.authSteps[scan.authStepIndex.clamp(0, scan.authSteps.length - 1)]),
                  style: context.text.titleMedium),
            ],
            if (done && (scan.verdict == Verdict.unavailable || scan.verdict == Verdict.possibleCounterfeit)) ...[
              const SizedBox(height: 4),
              for (final tip in checks)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.check_circle_outline_rounded, size: 20, color: context.colors.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Text(tip, style: context.text.bodyLarge)),
                  ]),
                ),
            ],
            if (done) ...[
              const SizedBox(height: 10),
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
    );
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
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3))
            : Icon(Icons.radio_button_unchecked_rounded, color: t.muted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
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
