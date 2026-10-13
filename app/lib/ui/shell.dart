import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/activity.dart';
import '../core/app_scope.dart';
import '../scan_controller.dart';
import '../services/announcer.dart';
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
/// foreground. Safety and counterfeit alerts pop up as banners on any tab.
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

  static const _activity = 1, _scanTab = 2, _wallet = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scope = AppScope.of(context);
      scope.scan.loadModels();
      _alerts = scope.activity.alerts.listen(_showBanner);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alerts?.cancel();
    _bannerTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final scan = AppScope.of(context).scan;
    if (state == AppLifecycleState.paused) {
      scan.stopCamera();
    } else if (state == AppLifecycleState.resumed && _tab == _scanTab) {
      scan.startCamera();
    }
  }

  void _showBanner(ActivityEvent e) {
    _bannerTimer?.cancel();
    setState(() => _banner = e);
    _bannerTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _banner = null);
    });
  }

  void _select(int i, {ScanMode? mode}) {
    final scan = AppScope.of(context).scan;
    if (mode != null) scan.setMode(mode);
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
      const SettingsScreen(),
    ];
    return Scaffold(
      extendBody: true,
      body: Stack(children: [
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
      ]),
      bottomNavigationBar: ListenableBuilder(
        listenable: scope.activity,
        builder: (context, _) => _NavBar(
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
  final int index;
  final int unread;
  final bool overCamera;
  final void Function(int) onSelect;
  const _NavBar({required this.index, required this.unread, required this.overCamera, required this.onSelect});

  static const _items = <(IconData, IconData, String)>[
    (NavIcons.home, NavIcons.homeFill, 'Home'),
    (NavIcons.bell, NavIcons.bellFill, 'Activity'),
    (NavIcons.scan, NavIcons.scanBold, 'Scan'),
    (NavIcons.wallet, NavIcons.walletFill, 'Wallet'),
    (NavIcons.gear, NavIcons.gearFill, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final dark = overCamera || context.isDark;
    final ink = dark ? Colors.white : context.colors.onSurface;
    final muted = dark ? Colors.white.withValues(alpha: 0.55) : t.muted;
    final bg = overCamera ? Colors.black.withValues(alpha: 0.6) : t.canvas.withValues(alpha: 0.9);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            border: Border(top: BorderSide(color: overCamera ? Colors.white10 : t.line)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 72,
              child: Row(children: [
                for (var i = 0; i < _items.length; i++)
                  Expanded(
                    child: i == 2
                        ? _ScanButton(selected: index == 2, onTap: () => onSelect(2), icon: _items[2].$2)
                        : _NavItem(
                            icon: index == i ? _items[i].$2 : _items[i].$1,
                            label: _items[i].$3,
                            selected: index == i,
                            ink: ink,
                            muted: muted,
                            dark: dark,
                            badge: i == 1 ? unread : 0,
                            onTap: () => onSelect(i),
                          ),
                  ),
              ]),
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
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.9,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
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
        ]),
      ),
    );
  }
}

/// The primary action: a slightly raised accent disc with a soft glow.
class _ScanButton extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final IconData icon;
  const _ScanButton({required this.selected, required this.onTap, required this.icon});

  @override
  Widget build(BuildContext context) {
    final a = context.colors.primary;
    return Semantics(
      selected: selected,
      button: true,
      label: 'Scan',
      excludeSemantics: true,
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
                  BoxShadow(color: a.withValues(alpha: selected ? 0.6 : 0.4), blurRadius: selected ? 22 : 16, offset: const Offset(0, 6)),
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
