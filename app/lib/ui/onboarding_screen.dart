import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/settings.dart';
import '../core/strings.dart';
import '../services/announcer.dart';
import 'theme.dart';
import 'widgets.dart';

class _Story {
  final IconData icon;
  final String title, body;
  final Color tint;
  const _Story(this.icon, this.title, this.body, this.tint);
}

List<_Story> _stories(S s) => [
  _Story(
    Icons.payments_rounded,
    s.t('Know every\nnote and coin.', 'Jua kila\nnoti na sarafu.'),
    s.t(
      'Point your camera at money from Kenya, Uganda, India, Egypt or the US. You hear its value right away.',
      'Elekeza kamera kwenye pesa za Kenya, Uganda, India, Misri au Marekani. Utasikia thamani yake mara moja.',
    ),
    const Color(0xFF22C55E),
  ),
  _Story(
    Icons.directions_walk_rounded,
    s.t('Walk with\nconfidence.', 'Tembea kwa\nujasiri.'),
    s.t(
      'Objects mode tells you what is around you, how far it is, and warns you early when something is in your path.',
      'Hali ya vitu inakueleza kilicho karibu nawe, kiko umbali gani, na inakuonya mapema kitu kikiwa njiani.',
    ),
    const Color(0xFF84CC16),
  ),
  _Story(
    Icons.record_voice_over_rounded,
    s.t('Just say\nwhat you need.', 'Sema tu\nunachohitaji.'),
    s.t(
      'Press and hold anywhere and speak: "scan money", "what is in front of me", "read my total".',
      'Bonyeza na ushikilie popote kisha sema: "soma pesa", "nini kiko mbele yangu", "jumla yangu".',
    ),
    const Color(0xFF15803D),
  ),
];

/// First launch: how the person uses the screen (two big halves, so a blind
/// user can answer without the voice guide), then language, voice and speed
/// (each spoken and previewed), then three story pages.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  bool _greeted = false;

  static const _setupPages = 4;
  int get _total => _setupPages + 3;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_greeted) {
      _greeted = true;
      // English and Kiswahili, so either speaker understands the first screen.
      final a = AppScope.of(context).scan.announcer;
      a.init().then((_) => a.say(_accessPrompt, priority: Priority.high));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  AppSettings get _settings => AppScope.of(context).settings;
  Announcer get _announcer => AppScope.of(context).scan.announcer;

  void _speakPage(int i) {
    final s = _settings.strings;
    final text = switch (i) {
      0 => _accessPrompt,
      1 => s.languagePrompt,
      2 => '${s.chooseVoice}. ${s.voiceWoman}, ${s.voiceMan}, ${s.voiceYoung}.',
      3 =>
        '${s.speechSpeed}. ${s.t('Use Slower and Faster, then Continue.', 'Tumia Polepole na Haraka, kisha Endelea.')}',
      _ => () {
        final st = _stories(s)[i - _setupPages];
        return '${st.title.replaceAll('\n', ' ')} ${st.body}';
      }(),
    };
    _announcer.say(text, priority: Priority.high, dedupe: Duration.zero);
  }

  void _go(int i) {
    if (i >= _total) {
      _finish();
      return;
    }
    _controller.animateToPage(i, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
  }

  void _finish() {
    final s = _settings;
    if (s.voiceGuide) {
      _announcer.say(s.strings.voiceGuideOn, priority: Priority.high, dedupe: Duration.zero);
      s.update((x) => x.guideIntroduced = true);
    }
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final s = settings.strings;
        final stories = _stories(s);
        final accent = context.colors.primary;
        final last = _page == _total - 1;
        final tint = _page < _setupPages ? accent : stories[_page - _setupPages].tint;
        return Scaffold(
          backgroundColor: context.tokens.canvas,
          body: AuroraBackground(
            colors: [tint.withValues(alpha: 0.35), accent.withValues(alpha: 0.2), Colors.white],
            intensity: 0.25,
            child: SizedBox.expand(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                  child: Column(
                    children: [
                      // Story-style progress segments
                      ExcludeSemantics(
                        child: Row(
                          children: [
                            for (var i = 0; i < _total; i++)
                              Expanded(
                                child: Container(
                                  height: 4,
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  decoration: BoxDecoration(
                                    color: context.tokens.line,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                  alignment: Alignment.centerLeft,
                                  child: AnimatedFractionallySizedBox(
                                    duration: const Duration(milliseconds: 400),
                                    widthFactor: i <= _page ? 1 : 0,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: accent,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Image.asset('assets/branding/logo.png', height: 30, excludeFromSemantics: true),
                          const SizedBox(width: 8),
                          Semantics(
                            label: 'NoteLens',
                            child: Image.asset('assets/branding/wordmark.png', height: 30, excludeFromSemantics: true),
                          ),
                          const Spacer(),
                          if (_page >= _setupPages)
                            TextButton(
                              onPressed: _finish,
                              style: TextButton.styleFrom(foregroundColor: context.colors.onSurface),
                              child: Text(s.skip),
                            ),
                        ],
                      ),
                      Expanded(
                        child: PageView(
                          controller: _controller,
                          onPageChanged: (i) {
                            setState(() => _page = i);
                            _speakPage(i);
                          },
                          children: [
                            _AccessPage(onPicked: () => _go(1)),
                            _LanguagePage(onPicked: () => _go(2)),
                            const _VoicePage(),
                            const _SpeedPage(),
                            for (final st in stories) _StoryPage(story: st),
                          ],
                        ),
                      ),
                      if (_page > 1)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () => _go(_page + 1),
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: context.colors.onPrimary,
                              minimumSize: const Size.fromHeight(64),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(last ? s.getStarted : s.continueLabel),
                                const SizedBox(width: 8),
                                Icon(last ? Icons.check_rounded : Icons.arrow_forward_rounded),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

const _accessPrompt =
    'Welcome to NoteLens. If you can see the screen, tap the top half. If you are blind or have low vision, '
    'tap the bottom half and I will read everything you touch. '
    'Karibu NoteLens. Kama unaona skrini, gusa nusu ya juu. Kama huoni au una uoni hafifu, gusa nusu ya chini.';

/// The screen split in two halves, so the choice works by touch alone.
class _AccessPage extends StatelessWidget {
  final VoidCallback onPicked;
  const _AccessPage({required this.onPicked});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    void pick(bool guide) {
      scope.settings.update((x) => x.voiceGuide = guide);
      scope.scan.announcer.say(
        guide
            ? 'Voice guide on. Touch anything to hear it, double tap to choose. '
                  'Mwongozo wa sauti umewashwa. Gusa kitu kusikia, gusa mara mbili kuchagua.'
            : 'Normal touch. Mguso wa kawaida.',
        priority: Priority.urgent,
        dedupe: Duration.zero,
        force: true,
      );
      onPicked();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Column(
        children: [
          Expanded(
            child: _BigChoice(
              label: 'I can see the screen\nNinaona skrini',
              icon: Icons.visibility_rounded,
              selected: false,
              onTap: () => pick(false),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _BigChoice(
              label: 'Read everything I touch\nNisomee kila ninachogusa',
              icon: Icons.record_voice_over_rounded,
              selected: false,
              onTap: () => pick(true),
            ),
          ),
        ],
      ),
    );
  }
}

/// Two huge buttons. Each says its name in its own language.
class _LanguagePage extends StatelessWidget {
  final VoidCallback onPicked;
  const _LanguagePage({required this.onPicked});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final s = scope.settings;
    return Column(
      children: [
        const SizedBox(height: 12),
        Semantics(
          header: true,
          child: Text(
            '${const S('en').chooseLanguage}\n${const S('sw').chooseLanguage}',
            textAlign: TextAlign.center,
            style: context.text.headlineMedium?.copyWith(color: context.colors.onSurface),
          ),
        ),
        const SizedBox(height: 20),
        for (final e in appLanguages.entries)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _BigChoice(
                label: e.value.$1,
                hint: S(e.key).t('Double tap to choose English.', 'Gusa mara mbili kuchagua Kiswahili.'),
                icon: Icons.translate_rounded,
                selected: s.language == e.key,
                onTap: () {
                  s.update(
                    (x) => x
                      ..language = e.key
                      ..voiceName = null,
                  );
                  scope.scan.announcer.preview(S(e.key).voiceSample);
                  onPicked();
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _VoicePage extends StatelessWidget {
  const _VoicePage();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final s = scope.settings;
    final L = s.strings;
    Widget choice(VoiceStyle v, String label, IconData icon) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: _BigChoice(
          label: label,
          icon: icon,
          selected: s.voiceStyle == v,
          onTap: () {
            s.update(
              (x) => x
                ..voiceStyle = v
                ..voiceName = null,
            );
            scope.scan.announcer.preview(L.voiceSample);
          },
        ),
      ),
    );
    return Column(
      children: [
        const SizedBox(height: 12),
        Semantics(
          header: true,
          child: Text(L.chooseVoice, style: context.text.headlineMedium?.copyWith(color: context.colors.onSurface)),
        ),
        const SizedBox(height: 16),
        choice(VoiceStyle.woman, L.voiceWoman, Icons.face_3_rounded),
        choice(VoiceStyle.man, L.voiceMan, Icons.face_6_rounded),
        choice(VoiceStyle.young, L.voiceYoung, Icons.child_care_rounded),
        if (scope.scan.announcer.languageMissing)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton.icon(
              onPressed: scope.scan.announcer.openVoiceSettings,
              style: TextButton.styleFrom(foregroundColor: context.colors.onSurface),
              icon: const Icon(Icons.download_rounded),
              label: Text(L.voiceMissing, textAlign: TextAlign.center),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _SpeedPage extends StatelessWidget {
  const _SpeedPage();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final s = scope.settings;
    final L = s.strings;
    void change(double d) {
      s.update((x) => x.speechRate = (x.speechRate + d).clamp(0.2, 0.9));
      scope.scan.announcer.preview(d > 0 ? L.speechFaster : L.speechSlower);
    }

    return Column(
      children: [
        const SizedBox(height: 12),
        Semantics(
          header: true,
          child: Text(L.speechSpeed, style: context.text.headlineMedium?.copyWith(color: context.colors.onSurface)),
        ),
        const Spacer(),
        ExcludeSemantics(
          child: Text(
            '${(s.speechRate * 200).round()}%',
            style: context.text.displayLarge?.copyWith(color: context.colors.onSurface, fontWeight: FontWeight.w800),
          ),
        ),
        const Spacer(),
        SizedBox(
          height: 120,
          child: Row(
            children: [
              Expanded(
                child: _BigChoice(
                  label: L.t('Slower', 'Polepole'),
                  icon: Icons.remove_rounded,
                  selected: false,
                  onTap: () => change(-0.1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BigChoice(
                  label: L.t('Faster', 'Haraka'),
                  icon: Icons.add_rounded,
                  selected: false,
                  onTap: () => change(0.1),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// A large, high-contrast, easy-to-hit choice.
class _BigChoice extends StatelessWidget {
  final String label;
  final String? hint;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _BigChoice({required this.label, this.hint, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.primary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      hint: hint,
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.96,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          width: double.infinity,
          decoration: BoxDecoration(
            color: selected ? accent : context.tokens.cardHigh,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: selected ? accent : context.tokens.line, width: 2),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 34, color: selected ? context.colors.onPrimary : context.colors.onSurface),
                const SizedBox(width: 14),
                Flexible(
                  child: Text(
                    label,
                    style: context.text.headlineSmall?.copyWith(
                      color: selected ? context.colors.onPrimary : context.colors.onSurface,
                      fontWeight: FontWeight.w800,
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

class _StoryPage extends StatelessWidget {
  final _Story story;
  const _StoryPage({required this.story});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: ExcludeSemantics(
          child: Center(child: _FloatingHero(icon: story.icon)),
        ),
      ),
      FadeSlideIn(
        key: ValueKey(story.title),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(story.title, style: context.text.displaySmall?.copyWith(color: context.colors.onSurface)),
            ),
            const SizedBox(height: 14),
            Text(
              story.body,
              style: context.text.titleMedium?.copyWith(color: context.tokens.muted, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      const SizedBox(height: 28),
    ],
  );
}

/// Frosted card with the page icon, bobbing gently, with orbiting dots.
class _FloatingHero extends StatefulWidget {
  final IconData icon;
  const _FloatingHero({required this.icon});

  @override
  State<_FloatingHero> createState() => _FloatingHeroState();
}

class _FloatingHeroState extends State<_FloatingHero> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 4));

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
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) {
      final t = _c.value * 2 * math.pi;
      return SizedBox(
        width: 260,
        height: 260,
        child: Stack(
          alignment: Alignment.center,
          children: [
            for (var k = 0; k < 3; k++)
              Transform.translate(
                offset: Offset(math.cos(t + k * 2.1) * 115, math.sin(t + k * 2.1) * 115),
                child: Container(
                  width: 14.0 - k * 3,
                  height: 14.0 - k * 3,
                  decoration: BoxDecoration(
                    color: context.colors.primary.withValues(alpha: 0.7 - k * 0.2),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            Transform.translate(
              offset: Offset(0, math.sin(t) * 8),
              child: Transform.rotate(
                angle: math.sin(t) * 0.04,
                child: Container(
                  decoration: BoxDecoration(
                    color: context.tokens.cardHigh,
                    borderRadius: BorderRadius.circular(48),
                    boxShadow: context.tokens.elevation,
                  ),
                  padding: const EdgeInsets.all(40),
                  child: Icon(widget.icon, size: 92, color: context.colors.primary),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
