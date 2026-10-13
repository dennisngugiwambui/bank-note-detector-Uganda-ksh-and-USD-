import 'dart:async';

import 'package:flutter/material.dart';

import '../core/activity.dart';
import '../core/app_scope.dart';
import '../scan_controller.dart';
import '../services/announcer.dart';
import 'activity_screen.dart';
import 'home_screen.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Main navigation: Home, Scan, Activity, Settings, with a floating pill bar.
/// The camera runs only while the Scan tab is visible and the app is in the
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

  static const _scanTab = 1;

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
    return Scaffold(
      extendBody: true,
      body: Stack(children: [
        IndexedStack(index: _tab, children: [
          HomeScreen(openScan: (m) => _select(_scanTab, mode: m), openActivity: () => _select(2)),
          // Built only while visible: the offstage camera spinner would otherwise keep redrawing.
          _tab == _scanTab ? const ScanScreen() : const SizedBox.shrink(),
          const ActivityScreen(),
          const SettingsScreen(),
        ]),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, a) => SlideTransition(
                position: Tween(begin: const Offset(0, -1.2), end: Offset.zero).animate(a),
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
        builder: (context, _) => _PillNav(
          index: _tab,
          unread: scope.activity.unread,
          onSelect: _select,
        ),
      ),
    );
  }
}

class _PillNav extends StatelessWidget {
  final int index;
  final int unread;
  final void Function(int) onSelect;
  const _PillNav({required this.index, required this.unread, required this.onSelect});

  static const _items = [
    (Icons.space_dashboard_rounded, 'Home'),
    (Icons.center_focus_strong_rounded, 'Scan'),
    (Icons.notifications_rounded, 'Activity'),
    (Icons.tune_rounded, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bar = dark ? const Color(0xFF22252C) : const Color(0xFF111318);
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        height: 72,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: bar,
          borderRadius: BorderRadius.circular(36),
          border: context.tokens.borderWidth > 0 ? Border.all(color: Colors.white, width: 2) : null,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: Row(children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              flex: i == index ? 2 : 1,
              child: Semantics(
                selected: i == index,
                button: true,
                label: i == 2 && unread > 0 ? '${_items[i].$2}, $unread unread' : _items[i].$2,
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () => onSelect(i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: i == index ? context.colors.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Badge(
                        isLabelVisible: i == 2 && unread > 0,
                        label: Text('$unread'),
                        child: Icon(_items[i].$1,
                            color: i == index ? context.colors.onPrimary : Colors.white.withValues(alpha: 0.75)),
                      ),
                      if (i == index) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(_items[i].$2,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: context.text.labelLarge?.copyWith(color: context.colors.onPrimary)),
                        ),
                      ],
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
