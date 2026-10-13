import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/currency.dart';
import '../core/settings.dart';
import 'theme.dart';
import 'widgets.dart';

/// Settings in WhatsApp / Instagram style: profile card, then grouped rows
/// with coloured icons and a live summary, each opening its own page.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final s = scope.settings;
    return ListenableBuilder(
      listenable: Listenable.merge([s, scope.auth, scope.scan]),
      builder: (context, _) {
        final user = scope.auth.currentUser;
        final guest = user == null || user.guest;
        void open(String title, WidgetBuilder body) => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (context) => _SubPage(title: title, child: body(context)),
            ));
        return SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
            children: [
              Semantics(header: true, child: Text('Settings', style: context.text.headlineLarge)),
              const SizedBox(height: 18),
              BentoCard(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  GradientRing(
                    size: 64,
                    seen: guest,
                    child: Container(
                      color: context.colors.primary,
                      alignment: Alignment.center,
                      child: Text(user?.firstName.characters.first.toUpperCase() ?? 'G',
                          style: context.text.headlineSmall?.copyWith(color: context.colors.onPrimary)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(user?.name ?? 'Guest', style: context.text.titleLarge),
                      Text(guest ? 'Guest · data stays on this phone' : user.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodyMedium?.copyWith(color: context.tokens.muted)),
                    ]),
                  ),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: scope.auth.signOut,
                    child: Text(guest ? 'Sign in' : 'Sign out'),
                  ),
                ]),
              ),
              const SizedBox(height: 20),
              _Group(children: [
                _NavRow(
                  icon: Icons.palette_rounded,
                  color: const Color(0xFF8B5CF6),
                  title: 'Appearance',
                  summary: '${_themeName(s.themeMode)}${s.highContrast ? ' · High contrast' : ''} · ${(s.textScale * 100).round()}%',
                  onTap: () => open('Appearance', (_) => const _AppearancePage()),
                ),
                _NavRow(
                  icon: Icons.record_voice_over_rounded,
                  color: const Color(0xFF10B981),
                  title: 'Voice & feedback',
                  summary: s.voiceEnabled
                      ? '${AppSettings.voiceLanguages[s.voiceLanguage] ?? s.voiceLanguage} · ${s.haptics ? 'Vibration on' : 'No vibration'}'
                      : 'Voice off',
                  onTap: () => open('Voice & feedback', (_) => const _VoicePage()),
                ),
              ]),
              const SizedBox(height: 14),
              _Group(children: [
                _NavRow(
                  icon: Icons.payments_rounded,
                  color: const Color(0xFF0EA5E9),
                  title: 'Money recognition',
                  summary: '${s.enabledCurrencies.length} currencies · ${scope.scan.hasCurrencyModel ? 'model ready' : 'model not installed'}',
                  onTap: () => open('Money recognition', (_) => const _MoneyPage()),
                ),
                _NavRow(
                  icon: Icons.verified_user_rounded,
                  color: const Color(0xFFF59E0B),
                  title: 'Counterfeit check',
                  summary: [
                    'Print',
                    if (s.backlightStep) 'light',
                    if (s.uvLampAvailable) 'UV',
                  ].join(' · '),
                  onTap: () => open('Counterfeit check', (_) => const _CounterfeitPage()),
                ),
                _NavRow(
                  icon: Icons.warning_amber_rounded,
                  color: const Color(0xFFEF4444),
                  title: 'Safety alerts',
                  summary: s.obstacleAlerts ? 'On · warn ${_closeness(s.obstacleCloseness).toLowerCase()}' : 'Off',
                  onTap: () => open('Safety alerts', (_) => const _SafetyPage()),
                ),
              ]),
              const SizedBox(height: 14),
              _Group(children: [
                _NavRow(
                  icon: Icons.info_rounded,
                  color: const Color(0xFF64748B),
                  title: 'About & privacy',
                  summary: 'Offline · version 0.3.0',
                  onTap: () => open('About & privacy', (_) => const _AboutPage()),
                ),
              ]),
            ],
          ),
        );
      },
    );
  }

  static String _themeName(ThemeMode m) => switch (m) {
        ThemeMode.system => 'Auto',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };
}

String _closeness(double v) => v < 0.2 ? 'Early' : v < 0.35 ? 'Normal' : 'Only when close';

// ---------------------------------------------------------------- pages

class _SubPage extends StatelessWidget {
  final String title;
  final Widget child;
  const _SubPage({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar.large(
          title: Text(title),
          backgroundColor: context.tokens.canvas,
          surfaceTintColor: Colors.transparent,
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          sliver: SliverToBoxAdapter(
            child: ListenableBuilder(
              listenable: Listenable.merge([scope.settings, scope.scan]),
              builder: (context, _) => FadeSlideIn(child: child),
            ),
          ),
        ),
      ]),
    );
  }
}

class _AppearancePage extends StatelessWidget {
  const _AppearancePage();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).settings;
    return Column(children: [
      _Group(children: [
        _Row(
          title: 'Theme',
          child: SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('Auto'), icon: Icon(Icons.brightness_auto_rounded)),
              ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_rounded)),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_rounded)),
            ],
            selected: {s.themeMode},
            onSelectionChanged: (v) => s.update((x) => x.themeMode = v.first),
          ),
        ),
        _Row(
          title: 'Accent colour',
          child: Wrap(spacing: 12, runSpacing: 12, children: [
            for (final c in AppSettings.accentChoices)
              Semantics(
                button: true,
                selected: s.accentColor == c.toARGB32(),
                label: 'Accent colour ${AppSettings.accentChoices.indexOf(c) + 1}',
                excludeSemantics: true,
                child: Pressable(
                  onTap: () => s.update((x) => x.accentColor = c.toARGB32()),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 46,
                    height: 46,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: s.accentColor == c.toARGB32() ? context.colors.onSurface : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                      child: s.accentColor == c.toARGB32()
                          ? const Icon(Icons.check_rounded, color: Colors.black, size: 20)
                          : null,
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ]),
      const SizedBox(height: 14),
      _Group(children: [
        _Switch('High contrast', 'Black and yellow, with thick outlines', s.highContrast,
            (v) => s.update((x) => x.highContrast = v)),
        _Slider('Text size', s.textScale, 0.9, 1.6, (v) => s.update((x) => x.textScale = v),
            label: '${(s.textScale * 100).round()}%'),
      ]),
      const SizedBox(height: 14),
      _Preview(),
    ]);
  }
}

/// Live preview card so changes are visible immediately.
class _Preview extends StatelessWidget {
  @override
  Widget build(BuildContext context) => BentoCard(
        gradient: LinearGradient(colors: [context.colors.primary, context.colors.secondary]),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Preview', style: context.text.labelLarge?.copyWith(color: context.colors.onPrimary)),
              const SizedBox(height: 6),
              Text('KSh 1,000', style: context.text.headlineMedium?.copyWith(color: context.colors.onPrimary)),
              Text('One thousand Kenyan shillings',
                  style: context.text.bodyMedium?.copyWith(color: context.colors.onPrimary.withValues(alpha: 0.8))),
            ]),
          ),
          Icon(Icons.payments_rounded, size: 44, color: context.colors.onPrimary),
        ]),
      );
}

class _VoicePage extends StatelessWidget {
  const _VoicePage();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final s = scope.settings;
    return Column(children: [
      _Group(children: [
        _Switch('Speak results', 'Announce notes, verdicts and alerts', s.voiceEnabled,
            (v) => s.update((x) => x.voiceEnabled = v)),
        _Slider('Speaking speed', s.speechRate, 0.2, 0.9, (v) => s.update((x) => x.speechRate = v),
            label: s.speechRate < 0.4 ? 'Slow' : s.speechRate < 0.6 ? 'Normal' : 'Fast'),
        _Slider('Pitch', s.pitch, 0.6, 1.6, (v) => s.update((x) => x.pitch = v), label: s.pitch.toStringAsFixed(1)),
        _Row(
          title: 'Voice',
          child: DropdownButtonFormField<String>(
            initialValue: s.voiceLanguage,
            isExpanded: true,
            borderRadius: BorderRadius.circular(20),
            items: [
              for (final e in AppSettings.voiceLanguages.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => s.update((x) => x.voiceLanguage = v ?? x.voiceLanguage),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => scope.scan.announcer
                  .say('One thousand Kenyan shillings. This is how I will sound.', dedupe: Duration.zero, force: true),
              icon: const Icon(Icons.volume_up_rounded),
              label: const Text('Test voice'),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 14),
      _Group(children: [
        _Switch('Vibration', 'Feel a pulse for results and warnings', s.haptics, (v) => s.update((x) => x.haptics = v)),
        _Switch('Announce running total', 'Say the wallet total after "Add"', s.announceTotals,
            (v) => s.update((x) => x.announceTotals = v)),
      ]),
    ]);
  }
}

class _MoneyPage extends StatelessWidget {
  const _MoneyPage();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final s = scope.settings;
    return Column(children: [
      if (!scope.scan.hasCurrencyModel) ...[
        BentoCard(
          color: context.tokens.warning.withValues(alpha: 0.14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_rounded, color: context.tokens.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'The banknote model is not installed in this build, so notes cannot be identified yet. '
                'These settings apply once it is.',
                style: context.text.bodyMedium,
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
      ],
      _Group(children: [
        _Slider('Certainty before speaking', s.sensitivity, 0.6, 0.97, (v) => s.update((x) => x.sensitivity = v),
            label: s.sensitivity < 0.75 ? 'Faster' : s.sensitivity < 0.9 ? 'Balanced' : 'Most certain'),
        _Switch('Automatic light', 'Turn on the flashlight in the dark', s.autoTorch,
            (v) => s.update((x) => x.autoTorch = v)),
      ]),
      const SizedBox(height: 14),
      _Group(children: [
        for (final c in currencyCatalog)
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            secondary: Text(c.flag, style: const TextStyle(fontSize: 28)),
            title: Text(currencyName(c.iso), style: context.text.titleMedium),
            subtitle: Text('${c.notes.length} notes · ${c.symbol}',
                style: context.text.bodyMedium?.copyWith(color: context.tokens.muted)),
            value: s.enabledCurrencies.contains(c.iso),
            onChanged: (on) => s.update((x) {
              final next = {...x.enabledCurrencies};
              on ? next.add(c.iso) : next.remove(c.iso);
              if (next.isNotEmpty) x.enabledCurrencies = next;
            }),
          ),
      ]),
    ]);
  }
}

class _CounterfeitPage extends StatelessWidget {
  const _CounterfeitPage();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final s = scope.settings;
    final c = scope.scan.authenticity;
    final supported = c == null ? 'loading' : [for (final x in currencyCatalog) if (c.supports(x.iso)) x.country].join(', ');
    return Column(children: [
      _Group(children: [
        _Switch('Watermark step', 'Hold the note against a window or lamp', s.backlightStep,
            (v) => s.update((x) => x.backlightStep = v)),
        _Switch('I have a UV lamp', 'Adds the ultraviolet step (365 nm lamp)', s.uvLampAvailable,
            (v) => s.update((x) => x.uvLampAvailable = v)),
      ]),
      const SizedBox(height: 14),
      BentoCard(
        child: Text(
          'Automatic checks installed for: ${supported.isEmpty ? 'none yet' : supported}. '
          'Every other currency gets spoken, step-by-step manual checks. '
          'This is a screening aid, not a guarantee.',
          style: context.text.bodyMedium?.copyWith(color: context.tokens.muted),
        ),
      ),
    ]);
  }
}

class _SafetyPage extends StatelessWidget {
  const _SafetyPage();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).settings;
    return _Group(children: [
      _Switch('Obstacle alerts', 'Warn about people, vehicles and objects in your path', s.obstacleAlerts,
          (v) => s.update((x) => x.obstacleAlerts = v)),
      _Slider('Warn me', s.obstacleCloseness, 0.1, 0.5, (v) => s.update((x) => x.obstacleCloseness = v),
          label: _closeness(s.obstacleCloseness)),
    ]);
  }
}

class _AboutPage extends StatelessWidget {
  const _AboutPage();

  @override
  Widget build(BuildContext context) {
    final scan = AppScope.of(context).scan;
    return _Group(children: [
      _Info('Banknote model', scan.hasCurrencyModel ? 'Installed' : 'Not installed'),
      _Info('Object model', scan.hasDetector ? 'EfficientDet-Lite2 · 80 objects' : 'Not installed'),
      _Info('Scene model', scan.hasSceneClassifier ? 'EfficientNet-Lite0 · 1000 things' : 'Not installed'),
      const _Info('Privacy', 'Works offline. Images never leave the phone.'),
      const _Info('Version', '0.3.0'),
    ]);
  }
}

// ---------------------------------------------------------------- rows

class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) => BentoCard(
        padding: const EdgeInsets.symmetric(vertical: 6),
        radius: 24,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(indent: 16, endIndent: 16, color: context.tokens.line),
            children[i],
          ],
        ]),
      );
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, summary;
  final VoidCallback onTap;
  const _NavRow({required this.icon, required this.color, required this.title, required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '$title. $summary',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              SquircleIcon(icon, color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: context.text.titleMedium),
                  Text(summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium?.copyWith(color: context.tokens.muted)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: context.tokens.muted),
            ]),
          ),
        ),
      );
}

class _Row extends StatelessWidget {
  final String title;
  final Widget child;
  const _Row({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: context.text.titleMedium),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: child),
        ]),
      );
}

class _Switch extends StatelessWidget {
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Switch(this.title, this.subtitle, this.value, this.onChanged);

  @override
  Widget build(BuildContext context) => SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        title: Text(title, style: context.text.titleMedium),
        subtitle: Text(subtitle, style: context.text.bodyMedium?.copyWith(color: context.tokens.muted)),
        value: value,
        onChanged: onChanged,
      );
}

class _Slider extends StatelessWidget {
  final String title, label;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  const _Slider(this.title, this.value, this.min, this.max, this.onChanged, {required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: context.text.titleMedium)),
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: context.tokens.cardHigh, borderRadius: BorderRadius.circular(12)),
              child: Text(label, style: context.text.labelLarge),
            ),
          ]),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            semanticFormatterCallback: (_) => label,
            onChanged: onChanged,
          ),
        ]),
      );
}

class _Info extends StatelessWidget {
  final String title, value;
  const _Info(this.title, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(title, style: context.text.titleMedium)),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.end, style: context.text.bodyMedium?.copyWith(color: context.tokens.muted)),
          ),
        ]),
      );
}
