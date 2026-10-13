import 'package:flutter/material.dart';

import '../core/activity.dart';
import '../core/app_scope.dart';
import '../core/currency.dart';
import '../scan_controller.dart';
import 'theme.dart';
import 'widgets.dart';

/// Bento dashboard: greeting, primary scan action, wallet totals, quick
/// actions and recent activity.
class HomeScreen extends StatelessWidget {
  final void Function(ScanMode) openScan;
  final VoidCallback openActivity;
  const HomeScreen({super.key, required this.openScan, required this.openActivity});

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
      builder: (context, _) => SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          children: [
            Row(children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: context.tokens.cardHigh,
                child: Text(
                  (user?.firstName.isNotEmpty ?? false) ? user!.firstName[0].toUpperCase() : '?',
                  style: context.text.titleLarge,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_greeting(), style: context.text.bodyMedium?.copyWith(color: context.tokens.muted)),
                  Text(user?.firstName ?? 'Guest', style: context.text.titleLarge),
                ]),
              ),
              IconButton.filledTonal(
                tooltip: 'Activity, ${scope.activity.unread} unread',
                onPressed: openActivity,
                icon: Badge(
                  isLabelVisible: scope.activity.unread > 0,
                  label: Text('${scope.activity.unread}'),
                  child: const Icon(Icons.notifications_rounded),
                ),
              ),
            ]),
            const SizedBox(height: 24),
            Semantics(
              header: true,
              child: Text('What would you\nlike to check?', style: context.text.displaySmall),
            ),
            const SizedBox(height: 20),
            _ScanHero(onTap: () => openScan(ScanMode.currency)),
            const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: _WalletCard(totals: scope.activity.totals, onClear: scope.activity.clearTotals)),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionTile(
                    icon: Icons.verified_user_rounded,
                    title: 'Check\nfor fakes',
                    subtitle: 'Print · light · UV',
                    color: const Color(0xFF8B7CF6),
                    onTap: () => openScan(ScanMode.currency),
                    semantic: 'Check for fakes. Identify a note in the scanner, then press Check fake.',
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: _ActionTile(
                    icon: Icons.visibility_rounded,
                    title: 'What\'s\naround me',
                    subtitle: scope.settings.obstacleAlerts ? 'Obstacle alerts on' : 'Alerts off',
                    color: const Color(0xFF38BDF8),
                    onTap: () => openScan(ScanMode.scene),
                    semantic: 'What is around me. Describes objects and warns about obstacles.',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _CurrenciesCard(enabled: scope.settings.enabledCurrencies)),
              ]),
            ),
            SectionTitle('Recent activity',
                trailing: TextButton(onPressed: openActivity, child: const Text('See all'))),
            if (scope.activity.events.isEmpty)
              BentoCard(
                child: Row(children: [
                  const IconBadge(Icons.history_rounded),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text('Notes you scan and alerts appear here.',
                        style: context.text.bodyLarge?.copyWith(color: context.tokens.muted)),
                  ),
                ]),
              )
            else
              for (final e in scope.activity.events.take(4)) ...[
                ActivityTile(event: e),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }
}

class _ScanHero extends StatelessWidget {
  final VoidCallback onTap;
  const _ScanHero({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final on = context.colors.onPrimary;
    return BentoCard(
      color: context.colors.primary,
      onTap: onTap,
      semanticLabel: 'Scan a banknote. Opens the camera and speaks the value.',
      padding: const EdgeInsets.all(24),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: on.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Text('Instant · Offline', style: context.text.labelLarge?.copyWith(color: on)),
            ),
            const SizedBox(height: 18),
            Text('Scan a\nbanknote', style: context.text.headlineMedium?.copyWith(color: on, height: 1.05)),
            const SizedBox(height: 6),
            Text('Hear the value out loud', style: context.text.bodyLarge?.copyWith(color: on.withValues(alpha: 0.75))),
          ]),
        ),
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(color: on, shape: BoxShape.circle),
          child: Icon(Icons.center_focus_strong_rounded, size: 40, color: context.colors.primary),
        ),
      ]),
    );
  }
}

class _WalletCard extends StatelessWidget {
  final Map<String, int> totals;
  final VoidCallback onClear;
  const _WalletCard({required this.totals, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final entries = totals.entries.toList();
    final summary = entries.isEmpty
        ? 'Wallet is empty'
        : entries.map((e) => '${e.value} ${currencyName(e.key)}').join(', ');
    return Semantics(
      label: 'Wallet total. $summary',
      child: BentoCard(
        color: const Color(0xFF111318), // always dark, in both themes
        child: ExcludeSemantics(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Wallet', style: context.text.titleMedium?.copyWith(color: Colors.white70)),
              const Spacer(),
              if (entries.isNotEmpty)
                InkWell(
                  onTap: onClear,
                  child: const Icon(Icons.restart_alt_rounded, color: Colors.white70, size: 20),
                ),
            ]),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              Text('0', style: context.text.displaySmall?.copyWith(color: Colors.white))
            else
              for (final e in entries.take(3))
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(formatAmount(e.key, e.value),
                      style: (entries.length == 1 ? context.text.headlineMedium : context.text.titleLarge)
                          ?.copyWith(color: Colors.white)),
                ),
            const SizedBox(height: 8),
            Text('Tap "Add" after a scan', style: context.text.bodySmall?.copyWith(color: Colors.white54)),
          ]),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle, semantic;
  final Color color;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    required this.semantic,
  });

  @override
  Widget build(BuildContext context) => BentoCard(
        onTap: onTap,
        semanticLabel: semantic,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconBadge(icon, background: color, foreground: Colors.black),
          const SizedBox(height: 18),
          Text(title, style: context.text.titleLarge?.copyWith(height: 1.1)),
          const SizedBox(height: 6),
          Text(subtitle, style: context.text.bodyMedium?.copyWith(color: context.tokens.muted)),
        ]),
      );
}

class _CurrenciesCard extends StatelessWidget {
  final Set<String> enabled;
  const _CurrenciesCard({required this.enabled});

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Currencies enabled: ${enabled.map(currencyName).join(', ')}',
        child: BentoCard(
          child: ExcludeSemantics(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Currencies', style: context.text.titleMedium),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final c in currencyCatalog)
                  Opacity(
                    opacity: enabled.contains(c.iso) ? 1 : 0.35,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: context.tokens.cardHigh, borderRadius: BorderRadius.circular(20)),
                      child: Text('${c.flag} ${c.iso}', style: context.text.labelLarge),
                    ),
                  ),
              ]),
            ]),
          ),
        ),
      );
}

/// Shared list tile for activity events.
class ActivityTile extends StatelessWidget {
  final ActivityEvent event;
  const ActivityTile({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final c = severityColor(context, event.severity);
    return BentoCard(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        IconBadge(activityIcon(event.kind, event.severity), background: c.withValues(alpha: 0.18), foreground: c, size: 46),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(event.title, style: context.text.titleMedium),
            if (event.detail.isNotEmpty)
              Text(event.detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium?.copyWith(color: context.tokens.muted)),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(timeAgo(event.time), style: context.text.bodySmall?.copyWith(color: context.tokens.muted)),
          if (!event.read)
            Container(
              margin: const EdgeInsets.only(top: 6),
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: context.colors.primary, shape: BoxShape.circle),
            ),
        ]),
      ]),
    );
  }
}
