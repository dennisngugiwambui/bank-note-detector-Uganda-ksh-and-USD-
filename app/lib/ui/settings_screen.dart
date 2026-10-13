import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/currency.dart';
import '../core/settings.dart';
import 'theme.dart';
import 'widgets.dart';

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
        return SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
            children: [
              Semantics(header: true, child: Text('Settings', style: context.text.displaySmall)),
              const SizedBox(height: 20),
              BentoCard(
                child: Row(children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: context.colors.primary,
                    child: Text(user?.firstName.characters.first.toUpperCase() ?? '?',
                        style: context.text.titleLarge?.copyWith(color: context.colors.onPrimary)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(user?.name ?? 'Guest', style: context.text.titleLarge),
                      Text(user == null || user.guest ? 'Guest mode · data stays on this phone' : user.email,
                          style: context.text.bodyMedium?.copyWith(color: context.tokens.muted)),
                    ]),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: scope.auth.signOut,
                    child: Text(user?.guest ?? true ? 'Sign in' : 'Sign out'),
                  ),
                ]),
              ),

              const SectionTitle('Appearance'),
              _Group(children: [
                _Row(
                  title: 'Theme',
                  child: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
                      ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                      ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                    ],
                    selected: {s.themeMode},
                    onSelectionChanged: (v) => s.update((x) => x.themeMode = v.first),
                  ),
                ),
                _Row(
                  title: 'Accent colour',
                  child: Wrap(spacing: 10, runSpacing: 10, children: [
                    for (final c in AppSettings.accentChoices)
                      Semantics(
                        button: true,
                        selected: s.accentColor == c.toARGB32(),
                        label: 'Accent colour ${AppSettings.accentChoices.indexOf(c) + 1}',
                        excludeSemantics: true,
                        child: GestureDetector(
                          onTap: () => s.update((x) => x.accentColor = c.toARGB32()),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: s.accentColor == c.toARGB32() ? context.colors.onSurface : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            child: s.accentColor == c.toARGB32() ? const Icon(Icons.check_rounded, color: Colors.black) : null,
                          ),
                        ),
                      ),
                  ]),
                ),
                _Switch('High contrast', 'Black and yellow, with thick outlines', s.highContrast,
                    (v) => s.update((x) => x.highContrast = v)),
                _Slider('Text size', s.textScale, 0.9, 1.6, (v) => s.update((x) => x.textScale = v),
                    label: '${(s.textScale * 100).round()}%'),
              ]),

              const SectionTitle('Voice & feedback'),
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
                    items: [
                      for (final e in AppSettings.voiceLanguages.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => s.update((x) => x.voiceLanguage = v ?? x.voiceLanguage),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: OutlinedButton.icon(
                    onPressed: () => scope.scan.announcer
                        .say('One thousand Kenyan shillings. This is how I will sound.', dedupe: Duration.zero, force: true),
                    icon: const Icon(Icons.record_voice_over_rounded),
                    label: const Text('Test voice'),
                  ),
                ),
                _Switch('Vibration', 'Feel a pulse for results and warnings', s.haptics, (v) => s.update((x) => x.haptics = v)),
                _Switch('Announce running total', 'Say the wallet total after "Add"', s.announceTotals,
                    (v) => s.update((x) => x.announceTotals = v)),
              ]),

              const SectionTitle('Money recognition'),
              _Group(children: [
                _Slider('Certainty before speaking', s.sensitivity, 0.6, 0.97, (v) => s.update((x) => x.sensitivity = v),
                    label: s.sensitivity < 0.75 ? 'Faster' : s.sensitivity < 0.9 ? 'Balanced' : 'Most certain'),
                _Switch('Automatic light', 'Turn on the flashlight in the dark', s.autoTorch,
                    (v) => s.update((x) => x.autoTorch = v)),
                _Row(
                  title: 'Currencies to recognise',
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final c in currencyCatalog)
                      FilterChip(
                        label: Text('${c.flag}  ${c.country}'),
                        selected: s.enabledCurrencies.contains(c.iso),
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: s.enabledCurrencies.contains(c.iso) ? context.colors.onPrimary : context.colors.onSurface,
                        ),
                        onSelected: (on) => s.update((x) {
                          final next = {...x.enabledCurrencies};
                          on ? next.add(c.iso) : next.remove(c.iso);
                          if (next.isNotEmpty) x.enabledCurrencies = next;
                        }),
                      ),
                  ]),
                ),
              ]),

              const SectionTitle('Counterfeit check'),
              _Group(children: [
                _Switch('Watermark step', 'Hold the note against a window or lamp', s.backlightStep,
                    (v) => s.update((x) => x.backlightStep = v)),
                _Switch('I have a UV lamp', 'Adds the ultraviolet step (365 nm lamp)', s.uvLampAvailable,
                    (v) => s.update((x) => x.uvLampAvailable = v)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Text(
                    'Automatic checks installed for: ${_authSupported(scope)}. Other currencies get guided manual checks.',
                    style: context.text.bodyMedium?.copyWith(color: context.tokens.muted),
                  ),
                ),
              ]),

              const SectionTitle('Safety alerts'),
              _Group(children: [
                _Switch('Obstacle alerts', 'Warn about people, vehicles and objects in your path', s.obstacleAlerts,
                    (v) => s.update((x) => x.obstacleAlerts = v)),
                _Slider('Warn me', s.obstacleCloseness, 0.1, 0.5, (v) => s.update((x) => x.obstacleCloseness = v),
                    label: s.obstacleCloseness < 0.2 ? 'Early' : s.obstacleCloseness < 0.35 ? 'Normal' : 'Only when close'),
              ]),

              const SectionTitle('About'),
              _Group(children: [
                _Info('Currency model', scope.scan.hasCurrencyModel ? 'Installed' : 'Not installed'),
                _Info('Object model', scope.scan.hasDetector ? 'EfficientDet-Lite0' : 'Not installed'),
                const _Info('Privacy', 'Works offline · images never leave the phone'),
                const _Info('Version', '0.2.0'),
              ]),
            ],
          ),
        );
      },
    );
  }

  String _authSupported(AppScope scope) {
    final c = scope.scan.authenticity;
    if (c == null) return 'loading';
    final list = [for (final x in currencyCatalog) if (c.supports(x.iso)) x.country];
    return list.isEmpty ? 'none yet' : list.join(', ');
  }
}

class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) => BentoCard(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: children),
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
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: context.text.titleMedium)),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(label, style: context.text.labelLarge?.copyWith(color: context.colors.primary)),
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
  Widget build(BuildContext context) => ListTile(
        title: Text(title, style: context.text.titleMedium),
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200),
          child: Text(value,
              textAlign: TextAlign.end, style: context.text.bodyMedium?.copyWith(color: context.tokens.muted)),
        ),
      );
}
