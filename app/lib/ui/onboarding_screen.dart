import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import 'theme.dart';

class _Page {
  final IconData icon;
  final String title;
  final String body;
  final String spoken;
  const _Page(this.icon, this.title, this.body, this.spoken);
}

const _pages = [
  _Page(Icons.payments_rounded, 'Know every\nnote instantly.',
      'Point your camera at a banknote from Kenya, Uganda, India, Egypt or the US. You hear its value right away.',
      'Welcome. Point your camera at a banknote and hear its value right away.'),
  _Page(Icons.verified_user_rounded, 'Spot fakes\nbefore you\'re fooled.',
      'A guided check looks at the print, the watermark against light and, with a UV lamp, the hidden features.',
      'A guided check helps you spot counterfeit notes.'),
  _Page(Icons.visibility_rounded, 'Hear what\'s\nin front of you.',
      'Objects mode describes your surroundings and warns you about people, vehicles and obstacles in your path.',
      'Objects mode describes your surroundings and warns you about obstacles.'),
];

/// First-launch walkthrough. Each page is read aloud, and every control is
/// reachable with TalkBack or VoiceOver.
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

  void _speak(int i) => AppScope.of(context).scan.announcer.say(_pages[i].spoken);

  void _next() {
    if (_page == _pages.length - 1) {
      widget.onDone();
    } else {
      _controller.nextPage(duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.primary;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            children: [
              Row(children: [
                Text('Banknote', style: context.text.titleLarge),
                Text('.', style: context.text.titleLarge?.copyWith(color: accent)),
                const Spacer(),
                TextButton(onPressed: widget.onDone, child: const Text('Skip')),
              ]),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) {
                    setState(() => _page = i);
                    _speak(i);
                  },
                  itemBuilder: (context, i) => _OnboardingPage(page: _pages[i], index: i),
                ),
              ),
              Row(children: [
                for (var i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.only(right: 8),
                    width: i == _page ? 28 : 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: i == _page ? accent : context.tokens.cardHigh,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                const Spacer(),
                Semantics(
                  label: _page == _pages.length - 1 ? 'Get started' : 'Next page',
                  button: true,
                  excludeSemantics: true,
                  child: FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(minimumSize: const Size(72, 72), shape: const CircleBorder()),
                    child: Icon(_page == _pages.length - 1 ? Icons.check_rounded : Icons.arrow_forward_rounded, size: 32),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  final _Page page;
  final int index;
  const _OnboardingPage({required this.page, required this.index});

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.primary;
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Expanded(
          child: ExcludeSemantics(
            child: Stack(alignment: Alignment.center, children: [
              // Layered bento tiles as the hero illustration
              Positioned(
                left: 0,
                top: 20,
                child: Transform.rotate(angle: -0.12, child: _tile(context, 170, 210, t.cardHigh)),
              ),
              Positioned(
                right: 0,
                bottom: 20,
                child: Transform.rotate(angle: 0.1, child: _tile(context, 150, 180, t.card)),
              ),
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(48)),
                child: Icon(page.icon, size: 96, color: context.colors.onPrimary),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 24),
        Semantics(header: true, child: Text(page.title, style: context.text.displaySmall)),
        const SizedBox(height: 16),
        Text(page.body, style: context.text.titleMedium?.copyWith(color: t.muted, fontWeight: FontWeight.w500)),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _tile(BuildContext context, double w, double h, Color c) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(36)),
      );
}
