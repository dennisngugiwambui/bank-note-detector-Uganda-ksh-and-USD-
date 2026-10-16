import 'package:flutter/material.dart';

import '../core/activity.dart';
import '../core/app_scope.dart';
import '../core/currency.dart';
import 'home_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Running totals per currency as swipeable bank cards, plus note history.
class WalletScreen extends StatefulWidget {
  final VoidCallback openScan;
  const WalletScreen({super.key, required this.openScan});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final _pages = PageController(viewportFraction: 0.88);
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final store = scope.activity;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final totals = store.totals.entries.toList();
        final notes = store.events.where((e) => e.kind == ActivityKind.note).toList();
        return SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(header: true, child: Text('Wallet', style: context.text.headlineLarge)),
                    ),
                    if (totals.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => _confirmReset(context, store),
                        icon: const Icon(Icons.restart_alt_rounded, size: 20),
                        label: const Text('Reset'),
                      ),
                  ],
                ),
              ),
              if (totals.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _EmptyCard(onScan: widget.openScan),
                )
              else
                SizedBox(
                  height: 210,
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: totals.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _BankCard(iso: totals[i].key, total: totals[i].value, index: i),
                    ),
                  ),
                ),
              if (totals.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < totals.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _page ? 22 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: i == _page ? context.colors.onSurface : context.tokens.line,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: FilledButton.icon(
                  onPressed: widget.openScan,
                  icon: const Icon(Icons.center_focus_strong_rounded),
                  label: const Text('Scan to add a note'),
                ),
              ),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: SectionTitle('Notes read')),
              if (notes.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Every note the scanner identifies is listed here.',
                    style: context.text.bodyLarge?.copyWith(color: context.tokens.muted),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: BentoCard(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(children: [for (final e in notes.take(30)) ActivityTile(event: e)]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmReset(BuildContext context, ActivityStore store) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset wallet?'),
        content: const Text('Totals go back to zero. The history of notes read is kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok == true) store.clearTotals();
  }
}

class _BankCard extends StatelessWidget {
  final String iso;
  final num total;
  final int index;
  const _BankCard({required this.iso, required this.total, required this.index});

  static const _palettes = [
    [Color(0xFF14532D), Color(0xFF15803D)],
    [Color(0xFF166534), Color(0xFF22C55E)],
    [Color(0xFF134E4A), Color(0xFF0F766E)],
    [Color(0xFF1A2E05), Color(0xFF4D7C0F)],
    [Color(0xFF052E16), Color(0xFF16A34A)],
  ];

  @override
  Widget build(BuildContext context) {
    final info = currencyInfo(iso);
    final colors = _palettes[index % _palettes.length];
    return Semantics(
      label: '${currencyName(iso)} total ${formatAmount(iso, total)}',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
          boxShadow: [
            BoxShadow(color: colors.last.withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 12)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: AuroraBackground(
          colors: [context.colors.primary, Colors.white],
          intensity: 0.12,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(info?.flag ?? '', style: const TextStyle(fontSize: 26)),
                    const SizedBox(width: 10),
                    Text(
                      currencyName(iso),
                      style: context.text.titleMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                    ),
                    const Spacer(),
                    Icon(Icons.contactless_rounded, color: Colors.white.withValues(alpha: 0.7)),
                  ],
                ),
                const Spacer(),
                Text('Total counted', style: context.text.bodyMedium?.copyWith(color: Colors.white70)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: total.toDouble()),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => Text(
                      formatAmount(iso, (v * 100).round() / 100),
                      style: context.text.displaySmall?.copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final VoidCallback onScan;
  const _EmptyCard({required this.onScan});

  @override
  Widget build(BuildContext context) => BentoCard(
    onTap: onScan,
    semanticLabel: 'Wallet is empty. Scan a note, then press Add.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const IconBadge(Icons.account_balance_wallet_rounded, size: 52),
        const SizedBox(height: 28),
        Text('Nothing counted yet', style: context.text.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Scan a note, then press Add. Totals are kept per currency.',
          style: context.text.bodyMedium?.copyWith(color: context.tokens.muted),
        ),
      ],
    ),
  );
}
