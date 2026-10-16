import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../scan_controller.dart';
import 'theme.dart';
import 'widgets.dart';

/// Shown while the on-device models start: a progress ring with the percent,
/// the seconds left and which parts are ready. Screen readers hear the same
/// as a live region. When the money model is missing from the build, it says
/// so plainly instead. Hides itself once everything is ready.
class ModelLoadingCard extends StatelessWidget {
  final bool compact;
  const ModelLoadingCard({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final scan = scope.scan;
    return ValueListenableBuilder<LoadProgress>(
      valueListenable: scan.loading,
      builder: (context, p, _) {
        final L = scope.settings.strings;
        if (p.done && scan.hasCurrencyModel) return const SizedBox.shrink();
        if (p.done) {
          return BentoCard(
            child: Semantics(
              liveRegion: true,
              child: Row(children: [
                const IconBadge(Icons.system_update_rounded),
                const SizedBox(width: 14),
                Expanded(child: Text(L.modelMissing, style: context.text.bodyLarge)),
              ]),
            ),
          );
        }
        final a = context.colors.primary;
        final parts = [
          (ModelPart.money, Icons.payments_rounded, L.t('Money', 'Pesa')),
          (ModelPart.objects, Icons.directions_walk_rounded, L.t('Obstacles', 'Vizuizi')),
          (ModelPart.scene, Icons.landscape_rounded, L.t('Scenes', 'Mandhari')),
        ];
        return Semantics(
          liveRegion: true,
          label: L.loadingStatus(p.percent, p.secondsLeft),
          excludeSemantics: true,
          child: BentoCard(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [a.withValues(alpha: 0.18), context.tokens.card],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                ConfidenceRing(
                  value: p.progress,
                  size: compact ? 64 : 84,
                  center: Text('${p.percent}%',
                      style: (compact ? context.text.titleMedium : context.text.titleLarge)
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(L.t('Getting ready', 'Inatayarishwa'), style: context.text.titleLarge),
                    const SizedBox(height: 4),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        L.t('About ${L.secondsWords(p.secondsLeft)} left',
                            'Takriban ${L.secondsWords(p.secondsLeft)} zimebaki'),
                        key: ValueKey(p.secondsLeft),
                        style: context.text.bodyLarge?.copyWith(color: context.tokens.muted),
                      ),
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: p.progress),
                  duration: const Duration(milliseconds: 300),
                  builder: (context, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 10,
                    backgroundColor: context.tokens.cardHigh,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (part, icon, name) in parts)
                  _PartChip(icon: icon, label: name, ready: p.finished.contains(part)),
              ]),
              if (!compact) ...[
                const SizedBox(height: 12),
                Text(
                  L.t('NoteLens is made for blind and low-vision people. Everything works offline, '
                      'and every result is spoken aloud.',
                      'NoteLens imetengenezwa kwa ajili ya watu wasioona na wenye uoni hafifu. '
                      'Kila kitu kinafanya kazi bila intaneti, na kila jibu linasomwa kwa sauti.'),
                  style: context.text.bodyMedium?.copyWith(color: context.tokens.muted),
                ),
              ],
            ]),
          ),
        );
      },
    );
  }
}

class _PartChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool ready;
  const _PartChip({required this.icon, required this.label, required this.ready});

  @override
  Widget build(BuildContext context) {
    final a = context.colors.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ready ? a.withValues(alpha: 0.18) : context.tokens.cardHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ready ? Icons.check_circle_rounded : icon, size: 18, color: ready ? a : context.tokens.muted),
        const SizedBox(width: 6),
        Text(label, style: context.text.labelLarge?.copyWith(color: ready ? a : null)),
      ]),
    );
  }
}
