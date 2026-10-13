import 'package:flutter/material.dart';

import '../core/activity.dart';
import '../core/app_scope.dart';
import 'home_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Notification centre: every scanned note, authenticity verdict and safety alert.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  ActivityKind? _filter;

  static const _filters = <(ActivityKind?, String)>[
    (null, 'All'),
    (ActivityKind.note, 'Notes'),
    (ActivityKind.authenticity, 'Authenticity'),
    (ActivityKind.obstacle, 'Alerts'),
  ];

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).activity;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final items = store.events.where((e) => _filter == null || e.kind == _filter).toList();
        final alerts = store.events.where((e) => e.kind == ActivityKind.obstacle).length;
        final flagged = store.events
            .where((e) => e.kind == ActivityKind.authenticity && e.severity == Severity.danger)
            .length;
        final notes = store.events.where((e) => e.kind == ActivityKind.note).length;
        return SafeArea(
          bottom: false,
          child: CustomScrollView(slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Semantics(header: true, child: Text('Activity', style: context.text.displaySmall))),
                    if (store.unread > 0)
                      TextButton(onPressed: store.markAllRead, child: const Text('Mark all read')),
                    IconButton(
                      tooltip: 'Clear history',
                      onPressed: store.events.isEmpty ? null : () => _confirmClear(context, store),
                      icon: const Icon(Icons.delete_sweep_rounded),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: _Stat(value: '$notes', label: 'Notes read', color: context.colors.primary)),
                    const SizedBox(width: 10),
                    Expanded(child: _Stat(value: '$flagged', label: 'Flagged', color: context.tokens.danger)),
                    const SizedBox(width: 10),
                    Expanded(child: _Stat(value: '$alerts', label: 'Alerts', color: context.tokens.warning)),
                  ]),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final f in _filters)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(f.$2),
                            selected: _filter == f.$1,
                            labelStyle: TextStyle(
                              color: _filter == f.$1 ? context.colors.onPrimary : context.colors.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                            onSelected: (_) => setState(() => _filter = f.$1),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                ]),
              ),
            ),
            if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const IconBadge(Icons.notifications_none_rounded, size: 72),
                    const SizedBox(height: 16),
                    Text('Nothing here yet', style: context.text.titleLarge),
                    const SizedBox(height: 6),
                    Text('Scans, verdicts and alerts will appear here.',
                        style: context.text.bodyLarge?.copyWith(color: context.tokens.muted)),
                  ]),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                sliver: SliverList.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => ActivityTile(event: items[i]),
                ),
              ),
          ]),
        );
      },
    );
  }

  Future<void> _confirmClear(BuildContext context, ActivityStore store) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text('This removes all scans, verdicts and alerts from this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) store.clear();
  }
}

class _Stat extends StatelessWidget {
  final String value, label;
  final Color color;
  const _Stat({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$value $label',
        excludeSemantics: true,
        child: BentoCard(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(height: 10),
            Text(value, style: context.text.headlineMedium),
            Text(label, style: context.text.bodyMedium?.copyWith(color: context.tokens.muted)),
          ]),
        ),
      );
}
