// Renders each main screen to PNG for visual review (not part of the normal suite).
//   flutter test test/preview --update-goldens
// Images land in test/preview/out/.
@Tags(['preview'])
library;

import 'dart:io';

import 'package:banknote_identifier/core/activity.dart';
import 'package:banknote_identifier/core/app_scope.dart';
import 'package:banknote_identifier/core/auth.dart';
import 'package:banknote_identifier/core/settings.dart';
import 'package:banknote_identifier/main.dart';
import 'package:banknote_identifier/scan_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFonts() async {
  Future<ByteData> file(String path) async => ByteData.sublistView(await File(path).readAsBytes());
  final inter = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    inter.addFont(file('assets/fonts/Inter-$w.ttf'));
  }
  await inter.load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? r'C:\Users\Softclans\dev\flutter';
  final icons = FontLoader('MaterialIcons')
    ..addFont(file('$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf'));
  await icons.load();
  for (final (family, f) in [
    ('PhosphorRegular', 'Phosphor-Regular.ttf'),
    ('PhosphorFill', 'Phosphor-Fill.ttf'),
    ('PhosphorBold', 'Phosphor-Bold.ttf'),
  ]) {
    await (FontLoader(family)..addFont(file('assets/fonts/$f'))).load();
  }
}

void main() {
  setUpAll(_loadFonts);

  Future<void> shot(WidgetTester tester, String name, {required ThemeMode theme, Future<void> Function()? go}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3; // 360 x 800 dp, like the user's phone
    addTearDown(tester.view.reset);
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    settings.update((s) {
      s.themeMode = theme;
      s.onboardingDone = !name.startsWith('onboarding') && !name.startsWith('auth');
    });
    final auth = await LocalAuthService.load();
    if (!name.startsWith('auth') && !name.startsWith('onboarding')) {
      await auth.signUp(name: 'Amina Otieno', email: 'amina@example.com', password: 'secret123');
    }
    final activity = await ActivityStore.load();
    if (name.contains('busy')) {
      activity.add(ActivityEvent(kind: ActivityKind.note, severity: Severity.success, title: 'KSh 1,000',
          detail: 'One thousand Kenyan shillings · 97% confidence'));
      activity.add(ActivityEvent(kind: ActivityKind.authenticity, severity: Severity.danger,
          title: 'USh 50,000 · Possible counterfeit', detail: 'Print: failed'), popUp: false);
      activity.add(ActivityEvent(kind: ActivityKind.obstacle, severity: Severity.warning, title: 'Person ahead',
          detail: 'In your path'));
      activity.add(ActivityEvent(kind: ActivityKind.note, severity: Severity.success, title: '\$ 20',
          detail: 'Twenty US dollars · 94% confidence'));
      activity.addToTotal('KES', 1500);
      activity.addToTotal('USD', 20);
    }
    final scan = ScanController(settings: settings, activity: activity);
    await tester.pumpWidget(AppScope(settings: settings, auth: auth, activity: activity, scan: scan, child: const BanknoteApp()));
    await tester.pumpAndSettle();
    if (go != null) await go();
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));
  }

  Future<void> Function() tab(WidgetTester t, String label) => () async {
        await t.tap(find.bySemanticsLabel(RegExp('^$label')));
        await t.pumpAndSettle();
      };

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    final n = theme.name;
    testWidgets('onboarding', (t) => shot(t, 'onboarding_$n', theme: theme));
    testWidgets('auth', (t) => shot(t, 'auth_$n', theme: theme, go: () async {
          await t.tap(find.text('Skip'));
          await t.pumpAndSettle();
        }));
    testWidgets('home', (t) => shot(t, 'home_busy_$n', theme: theme));
    testWidgets('home scrolled', (t) => shot(t, 'home_busy_scrolled_$n', theme: theme, go: () async {
          await t.drag(find.byType(Scrollable).first, const Offset(0, -600));
        }));
    testWidgets('activity', (t) => shot(t, 'activity_busy_$n', theme: theme, go: tab(t, 'Activity')));
    testWidgets('wallet', (t) => shot(t, 'wallet_busy_$n', theme: theme, go: tab(t, 'Wallet')));
    testWidgets('settings', (t) => shot(t, 'settings_$n', theme: theme, go: tab(t, 'Settings')));
    testWidgets('settings appearance', (t) => shot(t, 'settings_appearance_$n', theme: theme, go: () async {
          await tab(t, 'Settings')();
          await t.tap(find.text('Appearance'));
        }));
  }
}
