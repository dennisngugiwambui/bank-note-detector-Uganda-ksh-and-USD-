import 'package:flutter/material.dart';

import '../core/activity.dart';
import '../core/app_scope.dart';
import '../core/currency.dart';
import '../core/note_facts.dart';
import '../scan_controller.dart';
import '../services/command_center.dart';
import 'model_loading_card.dart';
import 'theme.dart';
import 'widgets.dart';

/// Home: brand bar, greeting, a voice "search" bar, one green hero card for
/// the main job, category chips, currency cards and recent activity. White
/// canvas, green cards. Every tile has a spoken label.
class HomeScreen extends StatelessWidget {
  final void Function(ScanMode) openScan;
  final VoidCallback openActivity;
  final VoidCallback openWallet;
  const HomeScreen({super.key, required this.openScan, required this.openActivity, required this.openWallet});

  String _greeting(AppScope scope) {
    final h = DateTime.now().hour;
    final s = scope.settings.strings;
    return h < 12
        ? s.t('Good morning', 'Habari za asubuhi')
        : h < 17
        ? s.t('Good afternoon', 'Habari za mchana')
        : s.t('Good evening', 'Habari za jioni');
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final user = scope.auth.currentUser;
    return ListenableBuilder(
      listenable: Listenable.merge([scope.activity, scope.scan, scope.settings]),
      builder: (context, _) {
        final scan = scope.scan;
        final L = scope.settings.strings;
        var i = 0;
        Widget item(Widget w) => FadeSlideIn(delay: FadeSlideIn.stagger(i++), child: w);
        return SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 130),
            children: [
              item(
                Row(
                  children: [
                    GradientRing(
                      size: 48,
                      child: Container(
                        color: context.tokens.cardHigh,
                        alignment: Alignment.center,
                        child: Text(
                          (user?.firstName.isNotEmpty ?? false) ? user!.firstName[0].toUpperCase() : 'G',
                          style: context.text.titleLarge,
                        ),
                      ),
                    ),
                    const Expanded(
                      child: Center(
                        child: Text(
                          'NOTELENS',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.5,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    _RoundButton(
                      icon: Icons.notifications_none_rounded,
                      badge: scope.activity.unread,
                      tooltip: '${L.activity}, ${L.unread(scope.activity.unread)}',
                      onTap: openActivity,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              item(
                Semantics(
                  header: true,
                  child: Text(
                    '${L.t('Hello', 'Habari')} ${user?.firstName ?? 'Guest'}',
                    style: context.text.headlineLarge,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              item(
                Text(
                  '${_greeting(scope)}. ${L.t('What would you like to check?', 'Ungependa kukagua nini?')}',
                  style: context.text.bodyLarge?.copyWith(color: context.tokens.muted),
                ),
              ),
              const SizedBox(height: 18),
              item(
                ValueListenableBuilder<bool>(
                  valueListenable: CommandCenter.instance.listening,
                  builder: (context, listening, _) => _VoiceBar(
                    text: listening ? L.listening : L.voiceCommand,
                    placeholder: L.t('Say “scan money”', 'Sema “soma pesa”'),
                    hint: L.voiceCommandHint,
                    listening: listening,
                    onTap: CommandCenter.instance.listen,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              item(
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    children: [
                      _Chip(
                        label: L.t('Money', 'Pesa'),
                        selected: true,
                        semantic: L.t('Money. Scan notes and coins.', 'Pesa. Soma noti na sarafu.'),
                        onTap: () => openScan(ScanMode.currency),
                      ),
                      _Chip(
                        label: L.t('Around me', 'Karibu nami'),
                        semantic: '${L.aroundMe}. ${L.aroundMeHint}',
                        onTap: () => openScan(ScanMode.scene),
                      ),
                      _Chip(
                        label: L.t('Fakes', 'Bandia'),
                        semantic: L.t(
                          'Check for fakes. Identify a note in the scanner, then press Check fake.',
                          'Kagua bandia. Tambua noti kwenye kamera, kisha bonyeza Kagua bandia.',
                        ),
                        onTap: () => openScan(ScanMode.currency),
                      ),
                      _Chip(
                        label: L.wallet,
                        semantic: '${L.wallet}. ${_walletLine(scope.activity.totals)}',
                        onTap: openWallet,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              item(
                ListenableBuilder(
                  listenable: scan.loading,
                  builder: (context, _) => scan.loading.value.done && scan.hasCurrencyModel
                      ? const SizedBox.shrink()
                      : const Padding(padding: EdgeInsets.only(bottom: 12), child: ModelLoadingCard()),
                ),
              ),
              item(
                _ScanHero(
                  label: '${L.scanMoney}. ${L.scanMoneyHint}',
                  title: L.t('Scan a\nbanknote', 'Soma\nnoti'),
                  subtitle: L.t('Point the camera. Hear the value.', 'Elekeza kamera. Sikia thamani.'),
                  button: L.t('Start scanning', 'Anza kusoma'),
                  onTap: () => openScan(ScanMode.currency),
                  modelReady: scan.hasCurrencyModel || !scan.modelsLoaded,
                ),
              ),
              const SizedBox(height: 12),
              item(
                Row(
                  children: [
                    Expanded(
                      child: _FeatureCard(
                        icon: Icons.directions_walk_rounded,
                        title: L.t('Around me', 'Karibu nami'),
                        subtitle: scope.settings.obstacleAlerts
                            ? L.t('Alerts on', 'Tahadhari zimewashwa')
                            : L.t('Alerts off', 'Tahadhari zimezimwa'),
                        semantic: '${L.aroundMe}. ${L.aroundMeHint}',
                        onTap: () => openScan(ScanMode.scene),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _FeatureCard(
                        icon: Icons.account_balance_wallet_rounded,
                        title: L.wallet,
                        subtitle: _walletLine(scope.activity.totals),
                        semantic: '${L.wallet}. ${_walletLine(scope.activity.totals)}',
                        onTap: openWallet,
                      ),
                    ),
                  ],
                ),
              ),
              item(
                SectionTitle(
                  L.t('Learn your money', 'Jifunze pesa zako'),
                  trailing: Text(
                    '${currencyCatalog.length}',
                    style: context.text.labelLarge?.copyWith(color: context.tokens.muted),
                  ),
                ),
              ),
              item(
                SizedBox(
                  height: 158,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    itemCount: currencyCatalog.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, k) {
                      final c = currencyCatalog[k];
                      return _CurrencyCard(
                        info: c,
                        enabled: scope.settings.enabledCurrencies.contains(c.iso),
                        semantic: L.t(
                          '${L.currencyName(c.iso)}. Notes, coins and how to check them.',
                          '${L.currencyName(c.iso)}. Noti, sarafu na jinsi ya kuzikagua.',
                        ),
                        onTap: () => showCurrencySheet(context, c),
                      );
                    },
                  ),
                ),
              ),
              item(
                SectionTitle(
                  L.t('Recent activity', 'Shughuli za karibuni'),
                  trailing: TextButton(onPressed: openActivity, child: Text(L.t('See all', 'Ona zote'))),
                ),
              ),
              item(
                scope.activity.events.isEmpty
                    ? BentoCard(
                        child: Row(
                          children: [
                            const IconBadge(Icons.history_rounded),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                L.t(
                                  'Money you scan, checks and alerts appear here.',
                                  'Pesa unazosoma, ukaguzi na tahadhari huonekana hapa.',
                                ),
                                style: context.text.bodyLarge?.copyWith(color: context.tokens.muted),
                              ),
                            ),
                          ],
                        ),
                      )
                    : BentoCard(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          children: [for (final e in scope.activity.events.take(4)) ActivityTile(event: e)],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _walletLine(Map<String, num> totals) {
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
    onTap: onTap,
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

/// The hero: a solid green card with white type, a white pill button and
/// the pulsing scan glyph.
class _ScanHero extends StatelessWidget {
  final String label, title, subtitle, button;
  final VoidCallback onTap;
  final bool modelReady;
  const _ScanHero({
    required this.label,
    required this.title,
    required this.subtitle,
    required this.button,
    required this.onTap,
    required this.modelReady,
  });

  @override
  Widget build(BuildContext context) {
    final a = context.colors.primary;
    final on = context.colors.onPrimary;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color.lerp(a, Colors.white, 0.12)!, a, Color.lerp(a, Colors.black, 0.18)!],
            ),
            boxShadow: [BoxShadow(color: a.withValues(alpha: 0.28), blurRadius: 26, offset: const Offset(0, 12))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned(
                right: -40,
                top: -40,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.08)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(modelReady ? Icons.bolt_rounded : Icons.info_outline_rounded, size: 15, color: on),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    modelReady ? 'Instant · Offline' : 'Update needed',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.text.labelMedium?.copyWith(color: on, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(title, style: context.text.headlineLarge?.copyWith(color: on, height: 1.02)),
                          ),
                          const SizedBox(height: 6),
                          Text(subtitle, style: context.text.bodyMedium?.copyWith(color: on.withValues(alpha: 0.85))),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    button,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.text.labelLarge?.copyWith(color: a),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(Icons.arrow_forward_rounded, size: 18, color: a),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const _PulsingScan(),
                  ],
                ),
              ),
            ],
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
        builder: (context, _) => Stack(
          alignment: Alignment.center,
          children: [
            for (final k in [0.0, 0.5])
              Builder(
                builder: (context) {
                  final v = (_c.value + k) % 1;
                  return Container(
                    width: 64 + 32 * v,
                    height: 64 + 32 * v,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: a.withValues(alpha: (1 - v) * 0.6), width: 2),
                    ),
                  );
                },
              ),
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
          ],
        ),
      ),
    );
  }
}

/// The voice "search" bar: looks like a search field, starts a voice command.
class _VoiceBar extends StatelessWidget {
  final String text, placeholder, hint;
  final bool listening;
  final VoidCallback onTap;
  const _VoiceBar({
    required this.text,
    required this.placeholder,
    required this.hint,
    required this.listening,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final a = context.colors.primary;
    return Semantics(
      button: true,
      label: text,
      hint: hint,
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          height: 60,
          padding: const EdgeInsets.only(left: 18, right: 6),
          decoration: BoxDecoration(
            color: listening ? a.withValues(alpha: 0.12) : context.tokens.cardHigh,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: listening ? a : Colors.transparent, width: 2),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: context.tokens.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(text, style: context.text.titleSmall),
                    Text(
                      placeholder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(color: context.tokens.muted),
                    ),
                  ],
                ),
              ),
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: context.colors.onSurface, borderRadius: BorderRadius.circular(24)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      listening ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                      color: context.colors.surface,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A rounded category chip; the selected one is filled green.
class _Chip extends StatelessWidget {
  final String label, semantic;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.semantic, required this.onTap, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final a = context.colors.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        label: semantic,
        excludeSemantics: true,
        onTap: onTap,
        child: Pressable(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? a : context.tokens.card,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: selected ? a : context.tokens.line),
            ),
            child: Text(
              label,
              style: context.text.labelLarge?.copyWith(
                color: selected ? context.colors.onPrimary : context.colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A light green card with an icon, title and one line.
class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title, subtitle, semantic;
  final VoidCallback onTap;
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.semantic,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final a = context.colors.primary;
    return Semantics(
      button: true,
      label: semantic,
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: context.tokens.cardHigh, borderRadius: BorderRadius.circular(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: context.tokens.card, shape: BoxShape.circle),
                    child: Icon(icon, color: a, size: 22),
                  ),
                  const Spacer(),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: context.tokens.card, shape: BoxShape.circle),
                    child: Icon(Icons.north_east_rounded, size: 16, color: context.colors.onSurface),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall?.copyWith(color: context.tokens.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A currency as a product-style card: flag on a green panel, name, counts.
class _CurrencyCard extends StatelessWidget {
  final CurrencyInfo info;
  final bool enabled;
  final String semantic;
  final VoidCallback onTap;
  const _CurrencyCard({required this.info, required this.enabled, required this.semantic, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final L = AppScope.of(context).settings.strings;
    return Semantics(
      button: true,
      label: semantic,
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        child: Container(
          width: 140,
          decoration: BoxDecoration(
            color: context.tokens.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: context.tokens.line),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(color: context.tokens.cardHigh, borderRadius: BorderRadius.circular(16)),
                  alignment: Alignment.center,
                  child: Opacity(
                    opacity: enabled ? 1 : 0.4,
                    child: Text(info.flag, style: const TextStyle(fontSize: 40)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            info.country,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.titleSmall,
                          ),
                          Text(
                            '${info.notes.length} ${L.t('notes', 'noti')} · ${info.coins.length} ${L.t('coins', 'sarafu')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelSmall?.copyWith(color: context.tokens.muted),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 20, color: context.tokens.muted),
                  ],
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet about one currency: its notes and how to check them by hand.
void showCurrencySheet(BuildContext context, CurrencyInfo c) {
  final scope = AppScope.of(context);
  final L = scope.settings.strings;
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
          return ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            children: [
              Row(
                children: [
                  Text(c.flag, style: const TextStyle(fontSize: 44)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(currencyName(c.iso), style: context.text.headlineSmall),
                        Text(
                          '${c.country} · ${c.symbol}',
                          style: context.text.bodyMedium?.copyWith(color: context.tokens.muted),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: on,
                    onChanged: (v) => scope.settings.update((x) {
                      final next = {...x.enabledCurrencies};
                      v ? next.add(c.iso) : next.remove(c.iso);
                      if (next.isNotEmpty) x.enabledCurrencies = next;
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(L.t('Know your notes and coins', 'Zijue noti na sarafu zako'), style: context.text.titleMedium),
              const SizedBox(height: 4),
              Text(
                L.t(
                  'Tap one to hear its colour, animal and what to feel for.',
                  'Gusa moja kusikia rangi yake, mnyama na unachoweza kuhisi.',
                ),
                style: context.text.bodyMedium?.copyWith(color: context.tokens.muted),
              ),
              const SizedBox(height: 10),
              for (final (note, fact) in factsOf(c))
                _FactRow(
                  note: note,
                  fact: fact,
                  onTap: () => scope.scan.announcer.say(detailsFor(note, L), dedupe: Duration.zero, force: true),
                ),
              const SizedBox(height: 24),
              Text('Check it by hand', style: context.text.titleMedium),
              const SizedBox(height: 6),
              if (checks.isEmpty)
                Text('Loading…', style: context.text.bodyMedium?.copyWith(color: context.tokens.muted))
              else
                for (var k = 0; k < checks.length; k++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: context.colors.primary, shape: BoxShape.circle),
                          child: Text(
                            '${k + 1}',
                            style: context.text.labelLarge?.copyWith(color: context.colors.onPrimary),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(checks[k], style: context.text.bodyLarge)),
                      ],
                    ),
                  ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => scope.scan.announcer.say(
                  '${currencyName(c.iso)}. ${checks.join(' ')}',
                  dedupe: Duration.zero,
                  force: true,
                ),
                icon: const Icon(Icons.volume_up_rounded),
                label: const Text('Read aloud'),
              ),
            ],
          );
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
        child: Row(
          children: [
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleMedium?.copyWith(
                      fontWeight: event.read ? FontWeight.w600 : FontWeight.w800,
                    ),
                  ),
                  if (event.detail.isNotEmpty)
                    Text(
                      event.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium?.copyWith(color: t.muted),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  timeAgo(event.time),
                  style: context.text.bodySmall?.copyWith(
                    color: event.read ? t.muted : context.colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One note or coin in the currency sheet: colour swatch, value, brief
/// feature. Tapping reads the full description aloud.
class _FactRow extends StatelessWidget {
  final Note note;
  final NoteFact? fact;
  final VoidCallback onTap;
  const _FactRow({required this.note, required this.fact, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final L = AppScope.of(context).settings.strings;
    final f = fact;
    final missing = f != null && !f.recognised;
    final name = note.spokenIn(L);
    final brief = f?.brief(L);
    final extra = missing
        ? L.t(
            'The camera does not know this coin yet. You can teach it in Settings.',
            'Kamera bado haijui sarafu hii. Unaweza kuifundisha kwenye Mipangilio.',
          )
        : null;
    return Semantics(
      button: true,
      label: [name, ?brief, ?extra].join('. '),
      excludeSemantics: true,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: BentoCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          onTap: onTap,
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: f?.colour == null ? context.tokens.cardHigh : Color(f!.colour!),
                  shape: note.coin ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: note.coin ? null : BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(note.coin ? Icons.circle_outlined : Icons.payments_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatAmount(note.currency, note.value) + (note.coin ? L.t(' coin', ' sarafu') : ''),
                      style: context.text.titleMedium,
                    ),
                    if (brief != null)
                      Text(brief, style: context.text.bodyMedium?.copyWith(color: context.tokens.muted)),
                    if (missing)
                      Text(
                        L.t('Not recognised yet · teach it', 'Bado haitambuliwi · ifundishe'),
                        style: context.text.labelMedium?.copyWith(color: context.colors.error),
                      ),
                  ],
                ),
              ),
              Icon(Icons.volume_up_rounded, color: context.colors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
