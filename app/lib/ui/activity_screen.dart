import 'package:flutter/material.dart';

import '../core/activity.dart';
import '../core/app_scope.dart';
import 'home_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Notification centre in WhatsApp's chat-list style: filter chips with
/// counts, day headers, swipe to delete (with undo), unread dots.
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
    (ActivityKind.authenticity, 'Fakes'),
    (ActivityKind.obstacle, 'Alerts'),
  ];

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).activity;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final items = store.events.where((e) => _filter == null || e.kind == _filter).toList();
        int count(ActivityKind? k) => k == null ? store.events.length : store.events.where((e) => e.kind == k).length;
        final flagged =
            store.events.where((e) => e.kind == ActivityKind.authenticity && e.severity == Severity.danger).length;

        // Rows with a header before each new day.
        final rows = <Widget>[];
        String? lastDay;
        for (var i = 0; i < items.length; i++) {
          final day = dayLabel(items[i].time);
          if (day != lastDay) {
            rows.add(_DayHeader(day));
            lastDay = day;
          }
          rows.add(_SwipeRow(event: items[i], store: store));
        }

        return SafeArea(
          bottom: false,
          child: CustomScrollView(slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
              sliver: SliverToBoxAdapter(
                child: Row(children: [
                  Expanded(child: Semantics(header: true, child: Text('Activity', style: context.text.headlineLarge))),
                  if (store.unread > 0)
                    TextButton.icon(
                      onPressed: store.markAllRead,
                      icon: const Icon(Icons.done_all_rounded, size: 20),
                      label: const Text('Read all'),
                    ),
                  IconButton(
                    tooltip: 'Clear history',
                    onPressed: store.events.isEmpty ? null : () => _confirmClear(context, store),
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Row(children: [
                  Expanded(child: _Stat(value: count(ActivityKind.note), label: 'Notes read', color: context.colors.primary)),
                  const SizedBox(width: 10),
                  Expanded(child: _Stat(value: flagged, label: 'Flagged', color: context.tokens.danger)),
                  const SizedBox(width: 10),
                  Expanded(child: _Stat(value: count(ActivityKind.obstacle), label: 'Alerts', color: context.tokens.warning)),
                ]),
              ),
            ),
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Row(children: [
                  for (final f in _filters)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(count(f.$1) > 0 ? '${f.$2}  ${count(f.$1)}' : f.$2),
                        selected: _filter == f.$1,
                        onSelected: (_) => setState(() => _filter = f.$1),
                      ),
                    ),
                ]),
              ),
            ),
            if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: FadeSlideIn(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [
                            context.colors.primary.withValues(alpha: 0.25),
                            context.colors.secondary.withValues(alpha: 0.12),
                          ]),
                        ),
                        child: Icon(Icons.notifications_none_rounded, size: 44, color: context.colors.primary),
                      ),
                      const SizedBox(height: 18),
                      Text('All caught up', style: context.text.titleLarge),
                      const SizedBox(height: 6),
                      Text('Scans, verdicts and alerts will appear here.',
                          style: context.text.bodyLarge?.copyWith(color: context.tokens.muted)),
                      const SizedBox(height: 100),
                    ]),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 120),
                sliver: SliverList.list(children: rows),
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

class _DayHeader extends StatelessWidget {
  final String label;
  const _DayHeader(this.label);

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(color: context.tokens.cardHigh, borderRadius: BorderRadius.circular(10)),
            child: Text(label, style: context.text.labelMedium?.copyWith(color: context.tokens.muted)),
          ),
        ),
      );
}

class _SwipeRow extends StatelessWidget {
  final ActivityEvent event;
  final ActivityStore store;
  const _SwipeRow({required this.event, required this.store});

  @override
  Widget build(BuildContext context) => Dismissible(
        key: ObjectKey(event),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          decoration: BoxDecoration(color: context.tokens.danger, borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.delete_rounded, color: Colors.white),
        ),
        onDismissed: (_) {
          final index = store.events.indexOf(event);
          store.remove(event);
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: const Text('Deleted'),
              action: SnackBarAction(label: 'Undo', onPressed: () => store.restore(event, index)),
            ));
        },
        child: ActivityTile(event: event),
      );
}

class _Stat extends StatelessWidget {
  final int value;
  final String label;
  final Color color;
  const _Stat({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$value $label',
        excludeSemantics: true,
        child: BentoCard(
          padding: const EdgeInsets.all(16),
          radius: 22,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(height: 10),
            TweenAnimationBuilder<double>(
              tween: Tween(end: value.toDouble()),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Text('${v.round()}', style: context.text.headlineMedium),
            ),
            Text(label, style: context.text.bodyMedium?.copyWith(color: context.tokens.muted)),
          ]),
        ),
      );
}
