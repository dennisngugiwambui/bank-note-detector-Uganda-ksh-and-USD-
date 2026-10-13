import 'package:banknote_identifier/core/activity.dart';
import 'package:banknote_identifier/core/app_scope.dart';
import 'package:banknote_identifier/core/auth.dart';
import 'package:banknote_identifier/core/currency.dart';
import 'package:banknote_identifier/core/settings.dart';
import 'package:banknote_identifier/main.dart';
import 'package:banknote_identifier/ml/authenticity_checker.dart';
import 'package:banknote_identifier/scan_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('LocalAuthService', () {
    test('sign up, sign out, sign in, wrong password', () async {
      final auth = await LocalAuthService.load();
      await auth.signUp(name: 'Amina Otieno', email: 'Amina@Example.com', password: 'secret123');
      expect(auth.currentUser!.firstName, 'Amina');
      await auth.signOut();
      expect(auth.isSignedIn, isFalse);
      await expectLater(auth.signIn(email: 'amina@example.com', password: 'wrongpass'), throwsA(isA<AuthException>()));
      await auth.signIn(email: 'amina@example.com', password: 'secret123');
      expect(auth.currentUser!.email, 'amina@example.com');
      // Session survives an app restart
      final again = await LocalAuthService.load();
      expect(again.currentUser!.name, 'Amina Otieno');
    });

    test('duplicate email is rejected', () async {
      final auth = await LocalAuthService.load();
      await auth.signUp(name: 'A', email: 'a@b.co', password: 'password1');
      await expectLater(auth.signUp(name: 'B', email: 'A@B.co', password: 'password2'), throwsA(isA<AuthException>()));
    });
  });

  test('settings persist across restarts', () async {
    final s = await AppSettings.load();
    s.update((x) {
      x.speechRate = 0.7;
      x.enabledCurrencies = {'KES', 'UGX'};
      x.highContrast = true;
    });
    final again = await AppSettings.load();
    expect(again.speechRate, 0.7);
    expect(again.enabledCurrencies, {'KES', 'UGX'});
    expect(again.highContrast, isTrue);
  });

  test('activity store keeps events and totals', () async {
    final a = await ActivityStore.load();
    a.add(ActivityEvent(kind: ActivityKind.note, title: 'KSh 100'));
    a.addToTotal('KES', 100);
    a.addToTotal('KES', 500);
    final again = await ActivityStore.load();
    expect(again.events.single.title, 'KSh 100');
    expect(again.totals['KES'], 600);
    expect(again.unread, 1);
  });

  test('formatAmount groups thousands', () {
    expect(formatAmount('UGX', 50000), 'USh 50,000');
    expect(formatAmount('USD', 5), r'$ 5');
  });

  test('authenticity verdict combines steps conservatively', () {
    const pass = StepResult(AuthStep.print, 0.05, 0.5);
    const unsure = StepResult(AuthStep.backlight, 0.35, 0.5);
    const fail = StepResult(AuthStep.uv, 0.8, 0.5);
    expect(AuthenticityChecker.combine([pass]), Verdict.noSignsOfCounterfeit);
    expect(AuthenticityChecker.combine([pass, unsure]), Verdict.uncertain);
    expect(AuthenticityChecker.combine([pass, fail]), Verdict.possibleCounterfeit);
    expect(AuthenticityChecker.combine([]), Verdict.unavailable);
  });

  testWidgets('first launch: onboarding → sign up → home dashboard', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // Looping decorative animations stay still, as for a user with reduce-motion on.
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final settings = await AppSettings.load();
    final auth = await LocalAuthService.load();
    final activity = await ActivityStore.load();
    final scan = ScanController(settings: settings, activity: activity);
    await tester.pumpWidget(AppScope(settings: settings, auth: auth, activity: activity, scan: scan, child: const BanknoteApp()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Know every'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Welcome'), findsOneWidget);
    await tester.tap(find.text('New here? Create an account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Full name'), 'Amina Otieno');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'amina@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'secret123');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Amina'), findsOneWidget); // greeting
    expect(find.textContaining('Scan a'), findsOneWidget);
    expect(find.text('Wallet'), findsWidgets); // services tile + nav bar
    expect(find.text('Learn your notes'), findsOneWidget);

    // Settings tab: open a sub-page, flip a toggle, it persists, come back.
    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Money recognition'), findsOneWidget);
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('High contrast'));
    await tester.pumpAndSettle();
    expect(settings.highContrast, isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('High contrast'), findsOneWidget); // summary row updated

    // Wallet and Activity tabs render
    await tester.tap(find.bySemanticsLabel('Wallet'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing counted yet'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('All caught up'), findsOneWidget);
  });
}
