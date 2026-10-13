import 'package:flutter/material.dart';

import '../core/activity.dart';
import '../core/app_scope.dart';
import '../core/currency.dart';
import '../scan_controller.dart';
import 'theme.dart';
import 'widgets.dart';

/// Home, laid out like Bolt's: greeting, one dominant call to action, a row
/// of currency "stories" (Instagram), service tiles, and recent activity in
/// WhatsApp's list style.
class HomeScreen extends StatelessWidget {
  final void Function(ScanMode) openScan;
  final VoidCallback openActivity;
  final VoidCallback openWallet;
  const HomeScreen({super.key, required this.openScan, required this.openActivity, required this.openWallet});

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final user = scope.auth.currentUser;
    return ListenableBuilder(
      listenable: Listenable.merge([scope.activity, scope.scan, scope.settings]),
      builder: (context, _) {
        final scan = scope.scan;
        var i = 0;
        Widget item(Widget w) => FadeSlideIn(delay: FadeSlideIn.stagger(i++), child: w);
        return SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
            children: [
              item(Row(children: [
                GradientRing(
                  size: 52,
                  child: Container(
                    color: context.tokens.cardHigh,
                    alignment: Alignment.center,
                    child: Text(
                      (user?.firstName.isNotEmpty ?? false) ? user!.firstName[0].toUpperCase() : 'G',
                      style: context.text.titleLarge,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_greeting(), style: context.text.bodyMedium?.copyWith(color: context.tokens.muted)),
                    Text(user?.firstName ?? 'Guest', style: context.text.titleLarge),
                  ]),
                ),
                _RoundButton(
                  icon: Icons.notifications_none_rounded,
                  badge: scope.activity.unread,
                  tooltip: 'Activity, ${scope.activity.unread} unread',
                  onTap: openActivity,
                ),
              ])),
              const SizedBox(height: 22),
              item(Semantics(
                header: true,
                child: Text('What would you\nlike to check?', style: context.text.displaySmall),
              )),
              const SizedBox(height: 18),
              item(_ScanHero(
                onTap: () => openScan(ScanMode.currency),
                modelReady: scan.hasCurrencyModel || !scan.modelsLoaded,
              )),
              const SizedBox(height: 12),
              item(_QuickPill(
                icon: Icons.visibility_rounded,
                text: 'What is in front of me?',
                onTap: () => openScan(ScanMode.scene),
              )),
              item(SectionTitle('Learn your notes',
                  trailing: Text('${scope.settings.enabledCurrencies.length} on',
                      style: context.text.labelLarge?.copyWith(color: context.tokens.muted)))),
              item(SizedBox(
                height: 104,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: currencyCatalog.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, k) {
                    final c = currencyCatalog[k];
                    final on = scope.settings.enabledCurrencies.contains(c.iso);
                    return Semantics(
                      button: true,
                      label: '${currencyName(c.iso)}. Notes and how to check them.',
                      excludeSemantics: true,
                      child: Pressable(
                        onTap: () => showCurrencySheet(context, c),
                        child: Column(children: [
                          GradientRing(
                            size: 72,
                            seen: !on,
                            child: Container(
                              color: context.tokens.cardHigh,
                              alignment: Alignment.center,
                              child: Text(c.flag, style: const TextStyle(fontSize: 32)),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(c.iso, style: context.text.labelLarge),
                        ]),
                      ),
                    );
                  },
                ),
              )),
              item(const SectionTitle('Services')),
              item(_ServicesGrid(
                tiles: [
                  _Service(Icons.payments_rounded, 'Money', 'Hear the value', context.colors.primary,
                      () => openScan(ScanMode.currency)),
                  _Service(Icons.verified_user_rounded, 'Fakes', 'Print · light · UV', const Color(0xFF8B7CF6),
                      () => openScan(ScanMode.currency),
                      semantic: 'Check for fakes. Identify a note in the scanner, then press Check fake.'),
                  _Service(Icons.visibility_rounded, 'Around me',
                      scope.settings.obstacleAlerts ? 'Alerts on' : 'Alerts off', const Color(0xFF38BDF8),
                      () => openScan(ScanMode.scene)),
                  _Service(Icons.account_balance_wallet_rounded, 'Wallet', _walletLine(scope.activity.totals),
                      const Color(0xFFFF8A4C), openWallet),
                ],
              )),
              item(SectionTitle('Recent activity',
                  trailing: TextButton(onPressed: openActivity, child: const Text('See all')))),
              item(scope.activity.events.isEmpty
                  ? BentoCard(
                      child: Row(children: [
                        const IconBadge(Icons.history_rounded),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text('Notes you scan, verdicts and alerts appear here.',
                              style: context.text.bodyLarge?.copyWith(color: context.tokens.muted)),
                        ),
                      ]),
                    )
                  : BentoCard(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(children: [
                        for (final e in scope.activity.events.take(4)) ActivityTile(event: e),
                      ]),
                    )),
            ],
          ),
        );
      },
    );
  }

  static String _walletLine(Map<String, int> totals) {
    if (totals.isEmpty) return 'Empty';
    final e = totals.entries.first;
    return formatAmount(e.key, e.value) + (totals.length > 1 ? ' +${totals.length - 1}' : '');
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final int badge;
  final String tooltip;
  final VoidCallback onTap;
  const _RoundButton({required this.icon, required this.badge, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: Pressable(
          onTap: onTap,
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: context.tokens.card,
              shape: BoxShape.circle,
              border: Border.all(color: context.tokens.line),
              boxShadow: context.tokens.elevation,
            ),
            child: Badge(
              isLabelVisible: badge > 0,
              backgroundColor: const Color(0xFFFF3B5C),
              label: Text('$badge'),
              offset: const Offset(-8, 6),
              alignment: Alignment.topRight,
              child: Center(child: Icon(icon, size: 26)),
            ),
          ),
        ),
      );
}

/// Primary action: gradient card with drifting colour and a pulsing scan glyph.
class _ScanHero extends StatelessWidget {
  final VoidCallback onTap;
  final bool modelReady;
  const _ScanHero({required this.onTap, required this.modelReady});

  @override
  Widget build(BuildContext context) {
    final a = context.colors.primary, b = context.colors.secondary;
    const on = Colors.white;
    return Semantics(
      button: true,
      label: 'Scan a banknote. Opens the camera and speaks the value.',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF13241C), Color(0xFF070B09)],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [BoxShadow(color: a.withValues(alpha: 0.18), blurRadius: 30, offset: const Offset(0, 14))],
          ),
          clipBehavior: Clip.antiAlias,
          child: AuroraBackground(
            colors: [a, b, a],
            intensity: 0.22,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(children: [
                Expanded(
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: a.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(modelReady ? Icons.bolt_rounded : Icons.info_outline_rounded, size: 16, color: a),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(modelReady ? 'Instant · Offline' : 'Model not installed',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.labelMedium?.copyWith(color: a, fontWeight: FontWeight.w700)),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 28),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('Scan a\nbanknote',
                          style: context.text.headlineLarge?.copyWith(color: on, height: 1.0)),
                    ),
                    const SizedBox(height: 6),
                    Text('Hear the value out loud', style: context.text.bodyLarge?.copyWith(color: on.withValues(alpha: 0.8))),
                  ]),
                ),
                const SizedBox(width: 8),
                const _PulsingScan(),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsingScan extends StatefulWidget {
  const _PulsingScan();

  @override
  State<_PulsingScan> createState() => _PulsingScanState();
}

class _PulsingScanState extends State<_PulsingScan> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

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
    final a = context.colors.primary;
    return SizedBox(
      width: 96,
      height: 96,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Stack(alignment: Alignment.center, children: [
          for (final k in [0.0, 0.5])
            Builder(builder: (context) {
              final v = (_c.value + k) % 1;
              return Container(
                width: 64 + 32 * v,
                height: 64 + 32 * v,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: a.withValues(alpha: (1 - v) * 0.6), width: 2),
                ),
              );
            }),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: a,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: a.withValues(alpha: 0.5), blurRadius: 20)],
            ),
            child: Icon(Icons.center_focus_strong_rounded, size: 32, color: context.colors.onPrimary),
          ),
        ]),
      ),
    );
  }
}

/// Bolt's "Where to?" pill: a big, calm secondary action.
class _QuickPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  const _QuickPill({required this.icon, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '$text Opens objects mode.',
        excludeSemantics: true,
        child: Pressable(
          onTap: onTap,
          child: Container(
            height: 64,
            padding: const EdgeInsets.only(left: 20, right: 8),
            decoration: BoxDecoration(
              color: context.tokens.card,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: context.tokens.line),
              boxShadow: context.tokens.elevation,
            ),
            child: Row(children: [
              Icon(icon, color: context.tokens.muted),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: context.text.titleMedium)),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: context.tokens.cardHigh, shape: BoxShape.circle),
                child: const Icon(Icons.arrow_forward_rounded),
              ),
            ]),
          ),
        ),
      );
}

class _Service {
  final IconData icon;
  final String title, subtitle;
  final Color color;
  final VoidCallback onTap;
  final String? semantic;
  const _Service(this.icon, this.title, this.subtitle, this.color, this.onTap, {this.semantic});
}

class _ServicesGrid extends StatelessWidget {
  final List<_Service> tiles;
  const _ServicesGrid({required this.tiles});

  @override
  Widget build(BuildContext context) => Column(children: [
        for (var r = 0; r < tiles.length; r += 2) ...[
          if (r > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _tile(context, tiles[r])),
              const SizedBox(width: 12),
              Expanded(child: r + 1 < tiles.length ? _tile(context, tiles[r + 1]) : const SizedBox()),
            ]),
          ),
        ],
      ]);

  Widget _tile(BuildContext context, _Service s) => BentoCard(
              onTap: s.onTap,
              semanticLabel: s.semantic ?? '${s.title}. ${s.subtitle}',
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color.lerp(s.color, Colors.white, 0.2)!, s.color],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(s.icon, color: ThemeData.estimateBrightnessForColor(s.color) == Brightness.dark ? Colors.white : Colors.black),
                ),
                const SizedBox(height: 22),
                Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleLarge),
                Text(s.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyMedium?.copyWith(color: context.tokens.muted)),
              ]),
            );
}

/// Bottom sheet about one currency: its notes and how to check them by hand.
void showCurrencySheet(BuildContext context, CurrencyInfo c) {
  final scope = AppScope.of(context);
  final checks = scope.scan.authenticity?.checksFor(c.iso) ?? const <String>[];
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      maxChildSize: 0.92,
      builder: (context, controller) => ListenableBuilder(
        listenable: scope.settings,
        builder: (context, _) {
          final on = scope.settings.enabledCurrencies.contains(c.iso);
          return ListView(controller: controller, padding: const EdgeInsets.fromLTRB(24, 0, 24, 32), children: [
            Row(children: [
              Text(c.flag, style: const TextStyle(fontSize: 44)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(currencyName(c.iso), style: context.text.headlineSmall),
                  Text('${c.country} · ${c.symbol}', style: context.text.bodyMedium?.copyWith(color: context.tokens.muted)),
                ]),
              ),
              Switch(
                value: on,
                onChanged: (v) => scope.settings.update((x) {
                  final next = {...x.enabledCurrencies};
                  v ? next.add(c.iso) : next.remove(c.iso);
                  if (next.isNotEmpty) x.enabledCurrencies = next;
                }),
              ),
            ]),
            const SizedBox(height: 20),
            Text('Notes', style: context.text.titleMedium),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final v in c.notes)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: context.tokens.cardHigh, borderRadius: BorderRadius.circular(14)),
                  child: Text(formatAmount(c.iso, v), style: context.text.labelLarge),
                ),
            ]),
            const SizedBox(height: 24),
            Text('Check it by hand', style: context.text.titleMedium),
            const SizedBox(height: 6),
            if (checks.isEmpty)
              Text('Loading…', style: context.text.bodyMedium?.copyWith(color: context.tokens.muted))
            else
              for (var k = 0; k < checks.length; k++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: context.colors.primary, shape: BoxShape.circle),
                      child: Text('${k + 1}',
                          style: context.text.labelLarge?.copyWith(color: context.colors.onPrimary)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(checks[k], style: context.text.bodyLarge)),
                  ]),
                ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => scope.scan.announcer
                  .say('${currencyName(c.iso)}. ${checks.join(' ')}', dedupe: Duration.zero, force: true),
              icon: const Icon(Icons.volume_up_rounded),
              label: const Text('Read aloud'),
            ),
          ]);
        },
      ),
    ),
  );
}

/// One activity row in WhatsApp's chat-list style: avatar, bold title,
/// one-line preview, time and an unread dot on the right.
class ActivityTile extends StatelessWidget {
  final ActivityEvent event;
  const ActivityTile({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final c = severityColor(context, event.severity);
    final t = context.tokens;
    return Semantics(
      label: '${event.title}. ${event.detail}. ${timeAgo(event.time)}${event.read ? '' : '. Unread'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [c.withValues(alpha: 0.28), c.withValues(alpha: 0.12)],
              ),
            ),
            child: Icon(activityIcon(event.kind, event.severity), color: c, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleMedium?.copyWith(fontWeight: event.read ? FontWeight.w600 : FontWeight.w800)),
              if (event.detail.isNotEmpty)
                Text(event.detail,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(color: t.muted)),
            ]),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(timeAgo(event.time),
                style: context.text.bodySmall?.copyWith(
                    color: event.read ? t.muted : context.colors.primary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            AnimatedOpacity(
              opacity: event.read ? 0 : 1,
              duration: const Duration(milliseconds: 300),
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: context.colors.primary, shape: BoxShape.circle),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

