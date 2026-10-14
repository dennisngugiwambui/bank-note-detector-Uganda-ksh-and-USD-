import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/currency.dart';
import '../core/settings.dart';
import '../core/strings.dart';
import '../ml/scene_speech.dart';
import '../services/announcer.dart';
import 'theme.dart';
import 'widgets.dart';

/// Settings in WhatsApp / Instagram style: profile card, then grouped rows
/// with coloured icons and a live summary, each opening its own page.
class SettingsScreen extends StatelessWidget {
  /// Opens the camera to teach a note.
  final void Function(Note note) onTeach;
  const SettingsScreen({super.key, required this.onTeach});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final s = scope.settings;
    return ListenableBuilder(
      listenable: Listenable.merge([s, scope.auth, scope.scan]),
      builder: (context, _) {
        final L = s.strings;
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
              Semantics(header: true, child: Text(L.settings, style: context.text.headlineLarge)),
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
                  title: L.t('Voice & language', 'Sauti na lugha'),
                  summary: s.voiceEnabled
                      ? '${appLanguages[s.language]?.$1 ?? s.language} · ${_styleName(L, s.voiceStyle)}'
                      : L.t('Voice off', 'Sauti imezimwa'),
                  onTap: () => open(L.t('Voice & language', 'Sauti na lugha'), (_) => const _VoicePage()),
                ),
                _NavRow(
                  icon: Icons.accessibility_new_rounded,
                  color: const Color(0xFF6366F1),
                  title: L.t('Voice guide & commands', 'Mwongozo na amri za sauti'),
                  summary: s.voiceGuide ? L.t('Voice guide on', 'Mwongozo umewashwa') : L.voiceGuideOff,
                  onTap: () => open(L.t('Voice guide & commands', 'Mwongozo na amri za sauti'), (_) => const _GuidePage()),
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
                  icon: Icons.directions_walk_rounded,
                  color: const Color(0xFFEF4444),
                  title: L.t('Surroundings', 'Mazingira'),
                  summary: s.obstacleAlerts
                      ? L.t('Warn within ${L.metres(s.warnDistance)}', 'Onya ndani ya ${L.metres(s.warnDistance)}')
                      : L.t('Alerts off', 'Tahadhari zimezimwa'),
                  onTap: () => open(L.t('Surroundings', 'Mazingira'), (_) => const _SafetyPage()),
                ),
                _NavRow(
                  icon: Icons.school_rounded,
                  color: const Color(0xFF14B8A6),
                  title: L.teachNote,
                  summary: scope.scan.canTeach
                      ? L.t('${scope.scan.taughtNotes?.examples.length ?? 0} taught',
                          '${scope.scan.taughtNotes?.examples.length ?? 0} zimefundishwa')
                      : L.t('Needs the money model', 'Inahitaji modeli ya pesa'),
                  onTap: () => open(L.teachNote, (_) => _TeachPage(onTeach: onTeach)),
                ),
              ]),
              const SizedBox(height: 14),
              _Group(children: [
                _NavRow(
                  icon: Icons.info_rounded,
                  color: const Color(0xFF64748B),
                  title: 'About & privacy',
                  summary: 'Offline · version 0.4.0',
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

String _styleName(S L, VoiceStyle v) => switch (v) {
      VoiceStyle.woman => L.voiceWoman,
      VoiceStyle.man => L.voiceMan,
      VoiceStyle.young => L.voiceYoung,
    };

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
                onTap: () => s.update((x) => x.accentColor = c.toARGB32()),
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
    final L = s.strings;
    final announcer = scope.scan.announcer;
    return Column(children: [
      _Group(children: [
        _Row(
          title: L.chooseLanguage,
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              for (final e in appLanguages.entries) ButtonSegment(value: e.key, label: Text(e.value.$1)),
            ],
            selected: {s.language},
            onSelectionChanged: (v) {
              s.update((x) => x
                ..language = v.first
                ..voiceName = null);
              announcer.preview(s.strings.voiceSample);
            },
          ),
        ),
        _Row(
          title: L.chooseVoice,
          child: SegmentedButton<VoiceStyle>(
            showSelectedIcon: false,
            segments: [
              for (final v in VoiceStyle.values) ButtonSegment(value: v, label: Text(_styleName(L, v))),
            ],
            selected: {s.voiceStyle},
            onSelectionChanged: (v) {
              s.update((x) => x
                ..voiceStyle = v.first
                ..voiceName = null);
              announcer.preview(L.voiceSample);
            },
          ),
        ),
        _Row(title: L.t('Exact voice', 'Sauti mahususi'), child: _VoicePicker(key: ValueKey(s.language))),
        if (announcer.languageMissing)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(L.voiceMissing, style: context.text.bodyMedium?.copyWith(color: context.tokens.warning)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => announcer.preview(L.voiceSample),
                icon: const Icon(Icons.volume_up_rounded),
                label: Text(L.t('Test voice', 'Jaribu sauti')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: announcer.openVoiceSettings,
                icon: const Icon(Icons.download_rounded),
                label: Text(L.t('More voices', 'Sauti zaidi')),
              ),
            ),
          ]),
        ),
      ]),
      const SizedBox(height: 14),
      _Group(children: [
        _Switch(L.t('Speak results', 'Ongea majibu'), L.t('Announce money, warnings and results', 'Tangaza pesa, tahadhari na majibu'),
            s.voiceEnabled, (v) => s.update((x) => x.voiceEnabled = v)),
        _Slider(L.speechSpeed, s.speechRate, 0.2, 0.9, (v) => s.update((x) => x.speechRate = v),
            label: s.speechRate < 0.4
                ? L.t('Slow', 'Polepole')
                : s.speechRate < 0.6
                    ? L.t('Normal', 'Kawaida')
                    : L.t('Fast', 'Haraka')),
        _Slider(L.t('Pitch', 'Kina cha sauti'), s.pitch, 0.6, 1.6, (v) => s.update((x) => x.pitch = v),
            label: s.pitch.toStringAsFixed(1)),
      ]),
      const SizedBox(height: 14),
      _Group(children: [
        _Switch(L.t('Vibration', 'Mtetemo'), L.t('Feel a pulse for results and warnings', 'Hisi mtetemo kwa majibu na tahadhari'),
            s.haptics, (v) => s.update((x) => x.haptics = v)),
        _Switch(L.t('Announce running total', 'Tangaza jumla'),
            L.t('Say the wallet total after "Add"', 'Sema jumla baada ya "Ongeza"'), s.announceTotals,
            (v) => s.update((x) => x.announceTotals = v)),
      ]),
    ]);
  }
}

/// Every voice for the chosen language, with a sample on select.
class _VoicePicker extends StatefulWidget {
  const _VoicePicker({super.key});

  @override
  State<_VoicePicker> createState() => _VoicePickerState();
}

class _VoicePickerState extends State<_VoicePicker> {
  Future<List<TtsVoice>>? _voices;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _voices ??= AppScope.of(context).scan.announcer.voices();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final s = scope.settings;
    final L = s.strings;
    return FutureBuilder<List<TtsVoice>>(
      future: _voices,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
        final list = snap.data ?? const <TtsVoice>[];
        if (list.isEmpty) {
          return Text(L.voiceMissing, style: context.text.bodyMedium?.copyWith(color: context.tokens.muted));
        }
        String name(TtsVoice v, int i) {
          final g = switch (v.gender) {
            VoiceGender.female => L.voiceWoman,
            VoiceGender.male => L.voiceMan,
            VoiceGender.unknown => L.t('Voice', 'Sauti'),
          };
          return '$g ${i + 1} · ${v.locale}${v.installed ? '' : L.t(' (download)', ' (pakua)')}';
        }

        return DropdownButtonFormField<String>(
          initialValue: list.any((v) => v.name == s.voiceName) ? s.voiceName : '',
          isExpanded: true,
          borderRadius: BorderRadius.circular(20),
          items: [
            DropdownMenuItem(value: '', child: Text(L.t('Automatic', 'Kiotomatiki'))),
            for (var i = 0; i < list.length; i++)
              DropdownMenuItem(value: list[i].name, child: Text(name(list[i], i), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) {
            s.update((x) => x.voiceName = (v == null || v.isEmpty) ? null : v);
            scope.scan.announcer.preview(L.voiceSample);
          },
        );
      },
    );
  }
}

class _GuidePage extends StatelessWidget {
  const _GuidePage();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).settings;
    final L = s.strings;
    return Column(children: [
      _Group(children: [
        _Switch(
            L.t('Voice guide', 'Mwongozo wa sauti'),
            L.t('Touch to hear, double tap to choose. Off while TalkBack is on.',
                'Gusa kusikia, gusa mara mbili kuchagua. Huzimwa TalkBack ikiwa imewashwa.'),
            s.voiceGuide,
            (v) => s.update((x) => x.voiceGuide = v)),
        _Switch(L.t('Listen when the app opens', 'Sikiliza programu ikifunguka'),
            L.t('Ready for a voice command right away', 'Tayari kwa amri ya sauti mara moja'), s.listenOnOpen,
            (v) => s.update((x) => x.listenOnOpen = v)),
        _Switch(
            L.t('Show pop-up alerts', 'Onyesha arifa za skrini'),
            L.t('For sighted helpers. Voice and vibration always work.',
                'Kwa wasaidizi wanaoona. Sauti na mtetemo hufanya kazi kila wakati.'),
            s.showAlertBanners,
            (v) => s.update((x) => x.showAlertBanners = v)),
      ]),
      const SizedBox(height: 14),
      BentoCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(L.t('Voice commands', 'Amri za sauti'), style: context.text.titleMedium),
          const SizedBox(height: 8),
          Text(L.commandsHelp, style: context.text.bodyMedium?.copyWith(color: context.tokens.muted)),
          const SizedBox(height: 8),
          Text(
              L.t('Press and hold anywhere to speak. From outside the app, say "Hey Google, open NoteLens", '
                  'or press and hold the NoteLens icon for shortcuts.',
                  'Bonyeza na ushikilie popote kuongea. Nje ya programu, sema "Hey Google, open NoteLens", '
                  'au bonyeza na ushikilie ikoni ya NoteLens kupata njia za mkato.'),
              style: context.text.bodyMedium?.copyWith(color: context.tokens.muted)),
        ]),
      ),
    ]);
  }
}

class _TeachPage extends StatelessWidget {
  final void Function(Note note) onTeach;
  const _TeachPage({required this.onTeach});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final s = scope.settings;
    final L = s.strings;
    final taught = scope.scan.taughtNotes;
    final items = [
      for (final c in currencyCatalog)
        if (s.enabledCurrencies.contains(c.iso)) ...[
          for (final v in c.notes) Note(c.iso, v),
          for (final v in c.coins) Note.parse('${c.iso}_${v}_coin')!,
        ],
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      BentoCard(child: Text(L.teachIntro, style: context.text.bodyMedium)),
      const SizedBox(height: 14),
      if (!scope.scan.canTeach)
        BentoCard(
          color: context.tokens.warning.withValues(alpha: 0.14),
          child: Text(L.t('Teaching needs the money model, which is not installed in this build.',
              'Kufundisha kunahitaji modeli ya pesa, ambayo haijasakinishwa.')),
        )
      else
        _Group(children: [
          for (final n in items)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: Text(currencyInfo(n.currency)?.flag ?? '', style: const TextStyle(fontSize: 24)),
              title: Text(n.spokenIn(L), style: context.text.titleMedium),
              subtitle: Text(
                  (taught?.count(n.label) ?? 0) > 0 ? L.taught(taught!.count(n.label)) : L.t('Not taught', 'Haijafundishwa'),
                  style: context.text.bodyMedium?.copyWith(color: context.tokens.muted)),
              trailing: (taught?.count(n.label) ?? 0) > 0
                  ? IconButton(
                      tooltip: L.t('Forget', 'Sahau'),
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () async {
                        await taught!.remove(n.label);
                        s.update((_) {}); // refresh the list
                      },
                    )
                  : const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.of(context).popUntil((r) => r.isFirst);
                onTeach(n);
              },
            ),
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
            subtitle: Text('${c.notes.length} notes · ${c.coins.length} coins · ${c.symbol}',
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
    final L = s.strings;
    return Column(children: [
      _Group(children: [
        _Switch(
            L.t('Obstacle alerts', 'Tahadhari za vizuizi'),
            L.t('Warn early about people, vehicles and things in your path',
                'Onya mapema kuhusu watu, magari na vitu njiani'),
            s.obstacleAlerts,
            (v) => s.update((x) => x.obstacleAlerts = v)),
        _Slider(L.t('Warn me from', 'Nionye kuanzia'), s.warnDistance, 1.5, 6,
            (v) => s.update((x) => x.warnDistance = v),
            label: L.metres(s.warnDistance)),
        _Switch(
            L.t('Proximity vibration', 'Mtetemo wa ukaribu'),
            L.t('Pulses faster as something in your path gets closer', 'Hutetemeka haraka kitu kikikaribia njiani'),
            s.proximityVibration,
            (v) => s.update((x) => x.proximityVibration = v)),
        _Switch(
            L.t('Money while walking', 'Pesa ukitembea'),
            L.t('Also announce notes and coins in Objects mode', 'Tangaza noti na sarafu pia katika hali ya vitu'),
            s.notesInObjectsMode,
            (v) => s.update((x) => x.notesInObjectsMode = v)),
      ]),
      const SizedBox(height: 14),
      _Group(children: [
        _Row(
          title: L.t('Distances in', 'Umbali kwa'),
          child: SegmentedButton<DistanceUnit>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: DistanceUnit.metres, label: Text(L.t('Metres', 'Mita'))),
              ButtonSegment(value: DistanceUnit.steps, label: Text(L.t('Steps', 'Hatua'))),
              ButtonSegment(value: DistanceUnit.none, label: Text(L.t('None', 'Hapana'))),
            ],
            selected: {s.distanceUnit},
            onSelectionChanged: (v) => s.update((x) => x.distanceUnit = v.first),
          ),
        ),
        _Row(
          title: L.t('Directions', 'Mwelekeo'),
          child: SegmentedButton<DirectionStyle>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: DirectionStyle.simple, label: Text(L.t('Left / right', 'Kushoto / kulia'))),
              ButtonSegment(value: DirectionStyle.clock, label: Text(L.t('Clock face', 'Saa'))),
            ],
            selected: {s.directionStyle},
            onSelectionChanged: (v) => s.update((x) => x.directionStyle = v.first),
          ),
        ),
      ]),
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
      const _Info('Version', '0.4.0'),
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
        onTap: onTap,
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
