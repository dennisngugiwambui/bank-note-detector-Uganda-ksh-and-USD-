import 'package:flutter/material.dart';

import '../core/settings.dart';

/// Design tokens. The style is bento-grid fintech: large rounded cards, one
/// bold accent on a calm canvas, oversized numbers. Every text/background
/// pair keeps at least 4.5:1 contrast, and high-contrast mode raises that further.
class AppTokens extends ThemeExtension<AppTokens> {
  final Color canvas;
  final Color card;
  final Color cardHigh;
  final Color muted;
  final Color success;
  final Color warning;
  final Color danger;
  final double radius;
  final double borderWidth;

  const AppTokens({
    required this.canvas,
    required this.card,
    required this.cardHigh,
    required this.muted,
    required this.success,
    required this.warning,
    required this.danger,
    this.radius = 28,
    this.borderWidth = 0,
  });

  @override
  AppTokens copyWith() => this;

  @override
  AppTokens lerp(AppTokens? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension TokensX on BuildContext {
  AppTokens get tokens => Theme.of(this).extension<AppTokens>()!;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}

ThemeData buildTheme(AppSettings s, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final hc = s.highContrast;
  final accent = hc ? const Color(0xFFFFD600) : Color(s.accentColor);
  final onAccent = ThemeData.estimateBrightnessForColor(accent) == Brightness.dark ? Colors.white : Colors.black;

  final tokens = AppTokens(
    canvas: hc ? Colors.black : (dark ? const Color(0xFF0B0C0F) : const Color(0xFFF2F3F5)),
    card: hc ? Colors.black : (dark ? const Color(0xFF16181D) : Colors.white),
    cardHigh: hc ? const Color(0xFF111111) : (dark ? const Color(0xFF20232A) : const Color(0xFFE9EBEF)),
    muted: hc ? Colors.white : (dark ? const Color(0xFF9BA1AB) : const Color(0xFF5F6670)),
    success: const Color(0xFF34D399),
    warning: const Color(0xFFFBBF24),
    danger: const Color(0xFFF87171),
    borderWidth: hc ? 2 : 0,
  );

  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: hc ? Brightness.dark : brightness).copyWith(
    primary: accent,
    onPrimary: onAccent,
    surface: tokens.card,
    onSurface: hc || dark ? Colors.white : const Color(0xFF111318),
    error: tokens.danger,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: scheme.brightness);
  final t = base.textTheme;
  final text = t.copyWith(
    displayLarge: t.displayLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.5, height: 1.0),
    displayMedium: t.displayMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.2, height: 1.05),
    displaySmall: t.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.1),
    headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
    headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
    titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.2),
  );

  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(20),
    side: hc ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
  );

  return base.copyWith(
    scaffoldBackgroundColor: tokens.canvas,
    textTheme: text,
    extensions: [tokens],
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.canvas,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: text.headlineSmall?.copyWith(color: scheme.onSurface),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 60),
        shape: shape,
        textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 60),
        shape: shape,
        side: BorderSide(color: hc ? Colors.white : scheme.outlineVariant, width: hc ? 2 : 1),
        textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.cardHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: hc ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: accent, width: 2),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: StadiumBorder(side: hc ? const BorderSide(color: Colors.white) : BorderSide.none),
      backgroundColor: tokens.cardHigh,
      selectedColor: accent,
      labelStyle: text.labelLarge,
      showCheckmark: false,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? onAccent : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : null),
    ),
    sliderTheme: base.sliderTheme.copyWith(activeTrackColor: accent, thumbColor: accent),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}
