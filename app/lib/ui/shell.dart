import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/activity.dart';
import '../core/app_scope.dart';
import '../core/currency.dart';
import '../scan_controller.dart';
import '../services/announcer.dart';
import '../services/command_center.dart';
import '../services/voice_commands.dart';
import 'activity_screen.dart';
import 'home_screen.dart';
import 'nav_icons.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'wallet_screen.dart';
import 'widgets.dart';

/// Main navigation: Home, Activity, Scan (centre), Wallet, Settings.
///
/// The bar follows Bolt: edge to edge, frosted, line icons (Phosphor) that
/// fill when selected with a soft accent pill behind them, and one raised
/// accent disc for the main action. Over the camera it turns dark.
/// The camera runs only while Scan is visible and the app is in the
/// foreground. Pop-up banners are off by default (blind users hear every
/// alert); a sighted helper can turn them on in Settings.
///
/// Voice commands (press and hold anywhere, the mic button, or an Android
/// shortcut / "Hey Google, open NoteLens") are handled here, since they
/// navigate between tabs.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _tab = 0;
  ActivityEvent? _banner;
  Timer? _bannerTimer;
  StreamSubscription<ActivityEvent>? _alerts;
  final VoiceCommands _voice = VoiceCommands();
  static const _system = MethodChannel('notelens/system');

  static const _home = 0, _activity = 1, _scanTab = 2, _wallet = 3, _settings = 4;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CommandCenter.instance.handler = _listen;
    _system.setMethodCallHandler((call) async {
      if (call.method == 'launchAction') _runLaunchAction(call.arguments as String?);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final scope = AppScope.of(context);
      _alerts = scope.activity.alerts.listen(_showBanner);
      await scope.scan.loadModels();
      if (!mounted) return;
      String? action;
      try {
        action = await _system.invokeMethod<String>('takeLaunchAction');
      } catch (_) {}
      if (!mounted) return;
      if (action != null) {
        _runLaunchAction(action);
      } else {
        final st = scope.settings;
        final explain = st.voiceGuide && !st.guideIntroduced && !MediaQuery.accessibleNavigationOf(context);
        scope.scan.announcer.say(
          explain ? '${st.strings.appReady} ${st.strings.voiceGuideOn}' : st.strings.appReady,
          priority: Priority.normal,
        );
        if (explain) st.update((x) => x.guideIntroduced = true);
        if (scope.settings.listenOnOpen) _listen();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (CommandCenter.instance.handler == _listen) CommandCenter.instance.handler = null;
    _alerts?.cancel();
    _bannerTimer?.cancel();
    _voice.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final scope = AppScope.of(context);
    final scan = scope.scan;
    if (state == AppLifecycleState.paused) {
      scan.stopCamera();
      _voice.cancel();
    } else if (state == AppLifecycleState.resumed) {
      if (_tab == _scanTab) scan.startCamera();
      _checkLaunchAction();
    }
  }

  Future<void> _checkLaunchAction() async {
    try {
      final a = await _system.invokeMethod<String>('takeLaunchAction');
      if (a != null) _runLaunchAction(a);
    } catch (_) {}
  }

  /// Actions from Android app shortcuts and assistant intents.
  void _runLaunchAction(String? action) {
    switch (action) {
      case 'scan_money':
        _select(_scanTab, mode: ScanMode.currency);
      case 'around_me':
        _select(_scanTab, mode: ScanMode.scene);
      case 'voice_command':
        _listen();
    }
  }

  // ---------------------------------------------------------------- voice

  Future<void> _listen() async {
    final scope = AppScope.of(context);
    final scan = scope.scan;
    final s = scope.settings.strings;
    if (_voice.listening) {
      await _voice.cancel();
      return;
    }
    await scan.announcer.stop();
    scan.announcer.buzz(Buzz.light);
    if (!await _voice.init()) {
      scan.announcer.say(s.micUnavailable, priority: Priority.high, force: true);
      return;
    }
    CommandCenter.instance.listening.value = true;
    final heard = await _voice.listen(scope.settings.speechLocale);
    CommandCenter.instance.listening.value = false;
    if (!mounted) return;
    final cmd = parseCommand(heard);
    if (cmd == null) {
      scan.announcer.say(s.didNotCatch, priority: Priority.high, dedupe: Duration.zero, force: true);
      return;
    }
    _run(cmd);
  }

  void _run(Command cmd) {
    final scope = AppScope.of(context);
    final scan = scope.scan;
    final settings = scope.settings;
    final s = settings.strings;
    void say(String t) => scan.announcer.say(t, priority: Priority.high, dedupe: Duration.zero, force: true);
    switch (cmd) {
      case Command.scanMoney:
        _select(_scanTab, mode: ScanMode.currency, announce: true);
      case Command.objects:
        if (_tab == _scanTab && scan.mode == ScanMode.scene) {
          scan.describeNow();
        } else {
          _select(_scanTab, mode: ScanMode.scene, announce: true);
        }
      case Command.total:
        say(scan.totalsSentence());
      case Command.add:
        scan.addToTotal();
      case Command.checkFake:
        if (_tab != _scanTab) _select(_scanTab, mode: ScanMode.currency);
        scan.checkAuthenticity();
      case Command.details:
        scan.describeNote();
      case Command.repeat:
        scan.repeatLast();
      case Command.light:
        if (_tab != _scanTab) _select(_scanTab);
        scan.toggleTorch();
      case Command.teach:
        _select(_settings);
        say(s.teachIntro);
      case Command.home:
        _select(_home);
        say(s.home);
      case Command.wallet:
        _select(_wallet);
        say(scan.totalsSentence());
      case Command.settings:
        _select(_settings);
        say(s.settings);
      case Command.activity:
        _select(_activity);
        say(s.activity);
      case Command.faster:
        settings.update((x) => x.speechRate = (x.speechRate + 0.1).clamp(0.2, 0.9));
        say(s.speechFaster);
      case Command.slower:
        settings.update((x) => x.speechRate = (x.speechRate - 0.1).clamp(0.2, 0.9));
        say(s.speechSlower);
      case Command.time:
        final now = DateTime.now();
        say(s.timeNow(now.hour, now.minute));
      case Command.help:
        say(s.commandsHelp);
      case Command.stop:
        scan.announcer.stop();
        if (_tab == _scanTab) _select(_home);
      case Command.guideOn:
        settings.update((x) => x.voiceGuide = true);
        say(s.voiceGuideOn);
      case Command.guideOff:
        settings.update((x) => x.voiceGuide = false);
        say(s.voiceGuideOff);
    }
  }

  void _teach(Note note) {
    _select(_scanTab, mode: ScanMode.currency);
    AppScope.of(context).scan.startTeach(note);
  }

  void _showBanner(ActivityEvent e) {
    if (!AppScope.of(context).settings.showAlertBanners) return;
    _bannerTimer?.cancel();
    setState(() => _banner = e);
    _bannerTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _banner = null);
    });
  }

  /// Opening the camera announces the mode itself, so the mode is only
  /// announced here when the scanner is already open.
  void _select(int i, {ScanMode? mode, bool announce = false}) {
    final scan = AppScope.of(context).scan;
    if (mode != null) {
      final already = i == _tab && scan.mode == mode;
      scan.setMode(mode, announce: i == _tab);
      if (already && announce) scan.repeatModeHint();
    }
    if (i == _tab) return;
    setState(() => _tab = i);
    scan.announcer.buzz(Buzz.light);
    if (i == _scanTab) {
      scan.startCamera();
    } else {
      scan.stopCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    scope.scan.announcer.screenReaderOn = MediaQuery.accessibleNavigationOf(context);
    final pages = [
      HomeScreen(
        openScan: (m) => _select(_scanTab, mode: m),
        openActivity: () => _select(_activity),
        openWallet: () => _select(_wallet),
      ),
      const ActivityScreen(),
      // Built only while visible: the offstage camera spinner would otherwise keep redrawing.
      _tab == _scanTab ? const ScanScreen() : const SizedBox.shrink(),
      WalletScreen(openScan: () => _select(_scanTab, mode: ScanMode.currency)),
      SettingsScreen(onTeach: _teach),
    ];
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          for (var i = 0; i < pages.length; i++)
            Offstage(
              offstage: i != _tab,
              child: TickerMode(
                enabled: i == _tab,
                child: AnimatedOpacity(
                  opacity: i == _tab ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: pages[i],
                ),
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOutBack,
                transitionBuilder: (child, a) => SlideTransition(
                  position: Tween(begin: const Offset(0, -1.4), end: Offset.zero).animate(a),
                  child: child,
                ),
                child: _banner == null
                    ? const SizedBox.shrink()
                    : AlertBanner(
                        key: ValueKey(_banner),
                        event: _banner!,
                        onClose: () => setState(() => _banner = null),
                      ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: scope.activity,
        builder: (context, _) => _NavBar(
          labels: [
            scope.settings.strings.home,
            scope.settings.strings.activity,
            scope.settings.strings.scan,
            scope.settings.strings.wallet,
            scope.settings.strings.settings,
          ],
          index: _tab,
          unread: scope.activity.unread,
          overCamera: _tab == _scanTab,
          onSelect: _select,
        ),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  final List<String> labels;
  final int index;
  final int unread;
  final bool overCamera;
  final void Function(int) onSelect;
  const _NavBar({
    required this.labels,
    required this.index,
    required this.unread,
    required this.overCamera,
    required this.onSelect,
  });

  static const _items = <(IconData, IconData)>[
    (NavIcons.home, NavIcons.homeFill),
    (NavIcons.bell, NavIcons.bellFill),
    (NavIcons.scan, NavIcons.scanBold),
    (NavIcons.wallet, NavIcons.walletFill),
    (NavIcons.gear, NavIcons.gearFill),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final dark = overCamera || context.isDark;
    final ink = dark ? Colors.white : context.colors.onSurface;
    final muted = dark ? Colors.white.withValues(alpha: 0.55) : t.muted;
    final bg = overCamera ? Colors.black.withValues(alpha: 0.6) : t.card.withValues(alpha: 0.92);
    // A floating pill, as in modern commerce apps.
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(36),
          boxShadow: overCamera
              ? null
              : [const BoxShadow(color: Color(0x1F0B3D1E), blurRadius: 30, offset: Offset(0, 10))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(36),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(36),
                border: Border.all(color: overCamera ? Colors.white10 : t.line),
              ),
              child: SizedBox(
                height: 72,
                child: Row(
                  children: [
                    for (var i = 0; i < _items.length; i++)
                      Expanded(
                        child: i == 2
                            ? _ScanButton(
                                selected: index == 2,
                                onTap: () => onSelect(2),
                                icon: _items[2].$2,
                                label: labels[2],
                              )
                            : _NavItem(
                                icon: index == i ? _items[i].$2 : _items[i].$1,
                                label: labels[i],
                                selected: index == i,
                                ink: ink,
                                muted: muted,
                                dark: dark,
                                badge: i == 1 ? unread : 0,
                                onTap: () => onSelect(i),
                              ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon over label; the active tab gets a soft accent pill behind a filled
/// icon (Bolt / Material 3 style), animated in.
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color ink, muted;
  final bool dark;
  final int badge;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.ink,
    required this.muted,
    required this.dark,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.primary;
    final pill = dark ? accent.withValues(alpha: 0.2) : Color.alphaBlend(accent.withValues(alpha: 0.45), Colors.white);
    return Semantics(
      selected: selected,
      button: true,
      label: badge > 0 ? '$label, $badge unread' : label,
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.9,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              width: selected ? 60 : 40,
              height: 32,
              decoration: BoxDecoration(
                color: selected ? pill : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Badge(
                  isLabelVisible: badge > 0,
                  backgroundColor: const Color(0xFFFF3B5C),
                  textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700),
                  label: Text(badge > 99 ? '99+' : '$badge'),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                    child: Icon(icon, key: ValueKey(icon), size: 24, color: selected ? (dark ? accent : ink) : muted),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11.5,
                letterSpacing: 0.1,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? ink : muted,
              ),
              child: Text(label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
            ),
          ],
        ),
      ),
    );
  }
}

/// The primary action: a slightly raised accent disc with a soft glow.
class _ScanButton extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final IconData icon;
  final String label;
  const _ScanButton({required this.selected, required this.onTap, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final a = context.colors.primary;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.9,
        child: Center(
          child: Transform.translate(
            offset: const Offset(0, -6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color.lerp(a, Colors.white, 0.25)!, a, Color.lerp(a, Colors.black, 0.18)!],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: selected ? 0.9 : 0.25), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: a.withValues(alpha: selected ? 0.6 : 0.4),
                    blurRadius: selected ? 22 : 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(icon, size: 28, color: context.colors.onPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
