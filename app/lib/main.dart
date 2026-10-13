import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/activity.dart';
import 'core/app_scope.dart';
import 'core/auth.dart';
import 'core/settings.dart';
import 'scan_controller.dart';
import 'ui/auth_screen.dart';
import 'ui/onboarding_screen.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final settings = await AppSettings.load();
  final auth = await LocalAuthService.load(); // swap for a cloud AuthService here
  final activity = await ActivityStore.load();
  final scan = ScanController(settings: settings, activity: activity);
  runApp(AppScope(
    settings: settings,
    auth: auth,
    activity: activity,
    scan: scan,
    child: const BanknoteApp(),
  ));
}

class BanknoteApp extends StatelessWidget {
  const BanknoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.settings, scope.auth]),
      builder: (context, _) {
        final s = scope.settings;
        return MaterialApp(
          title: 'Banknote',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(s, Brightness.light),
          darkTheme: buildTheme(s, Brightness.dark),
          themeMode: s.highContrast ? ThemeMode.dark : s.themeMode,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(MediaQuery.textScalerOf(context).scale(1) * s.textScale),
            ),
            child: child!,
          ),
          home: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: !s.onboardingDone
                ? OnboardingScreen(key: const ValueKey('onboarding'), onDone: () => s.update((x) => x.onboardingDone = true))
                : !scope.auth.isSignedIn
                    ? const AuthScreen(key: ValueKey('auth'))
                    : const AppShell(key: ValueKey('shell')),
          ),
        );
      },
    );
  }
}
