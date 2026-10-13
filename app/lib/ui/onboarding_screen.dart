import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import 'theme.dart';
import 'widgets.dart';

class _Page {
  final IconData icon;
  final String title;
  final String body;
  final String spoken;
  final Color tint;
  const _Page(this.icon, this.title, this.body, this.spoken, this.tint);
}

const _pages = [
  _Page(
    Icons.payments_rounded,
    'Know every\nnote instantly.',
    'Point your camera at a banknote from Kenya, Uganda, India, Egypt or the US. You hear its value right away.',
    'Welcome. Point your camera at a banknote and hear its value right away.',
    Color(0xFF22D3EE),
  ),
  _Page(
    Icons.verified_user_rounded,
    'Spot fakes\nbefore you\'re fooled.',
    'A guided check looks at the print, the watermark against light and, with a UV lamp, the hidden features.',
    'A guided check helps you spot counterfeit notes.',
    Color(0xFF8B5CF6),
  ),
  _Page(
    Icons.visibility_rounded,
    'Hear what\'s\nin front of you.',
    'Objects mode describes your surroundings and warns you about people, vehicles and obstacles in your path.',
    'Objects mode describes your surroundings and warns you about obstacles.',
    Color(0xFFFF4D8D),
  ),
];

/// First-launch walkthrough in the style of Instagram stories: segmented
/// progress on top, immersive colour, big type. Each page is read aloud and
/// every control works with TalkBack or VoiceOver.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_page == 0) _speak(0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _speak(int i) => AppScope.of(context).scan.announcer.say(_pages[i].spoken);

  void _next() {
    if (_page == _pages.length - 1) {
      widget.onDone();
    } else {
      _controller.nextPage(duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.primary;
    final last = _page == _pages.length - 1;
    return Scaffold(
      backgroundColor: Colors.black,
      body: AuroraBackground(
        colors: [_pages[_page].tint, accent, const Color(0xFF1E1B4B)],
        intensity: 0.5,
        child: SizedBox.expand(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: Column(
                children: [
                  // Story-style progress segments
                  Row(
                    children: [
                      for (var i = 0; i < _pages.length; i++)
                        Expanded(
                          child: Container(
                            height: 4,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                            alignment: Alignment.centerLeft,
                            child: AnimatedFractionallySizedBox(
                              duration: const Duration(milliseconds: 400),
                              widthFactor: i <= _page ? 1 : 0,
                              child: Container(
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
                              ),
                            ),
                          ),
                        ),
                    ],
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
                      TextButton(
                        onPressed: widget.onDone,
                        style: TextButton.styleFrom(foregroundColor: Colors.white),
                        child: const Text('Skip'),
                      ),
                    ],
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: _pages.length,
                      onPageChanged: (i) {
                        setState(() => _page = i);
                        _speak(i);
                      },
                      itemBuilder: (context, i) => _OnboardingPage(page: _pages[i]),
                    ),
                  ),
                  Semantics(
                    label: last ? 'Get started' : 'Next page',
                    button: true,
                    excludeSemantics: true,
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _next,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          minimumSize: const Size.fromHeight(60),
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Row(
                            key: ValueKey(last),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(last ? 'Get started' : 'Continue'),
                              const SizedBox(width: 8),
                              Icon(last ? Icons.check_rounded : Icons.arrow_forward_rounded),
                            ],
                          ),
                        ),
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
  }
}

class _OnboardingPage extends StatelessWidget {
  final _Page page;
  const _OnboardingPage({required this.page});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: ExcludeSemantics(
          child: Center(child: _FloatingHero(page: page)),
        ),
      ),
      FadeSlideIn(
        key: ValueKey(page.title),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(page.title, style: context.text.displaySmall?.copyWith(color: Colors.white)),
            ),
            const SizedBox(height: 14),
            Text(
              page.body,
              style: context.text.titleMedium?.copyWith(color: Colors.white70, fontWeight: FontWeight.w500),
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
  final _Page page;
  const _FloatingHero({required this.page});

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
                    color: Colors.white.withValues(alpha: 0.7 - k * 0.2),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            Transform.translate(
              offset: Offset(0, math.sin(t) * 8),
              child: Transform.rotate(
                angle: math.sin(t) * 0.04,
                child: GlassPanel(
                  radius: 48,
                  tint: 0.18,
                  padding: const EdgeInsets.all(40),
                  child: Icon(widget.page.icon, size: 92, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
