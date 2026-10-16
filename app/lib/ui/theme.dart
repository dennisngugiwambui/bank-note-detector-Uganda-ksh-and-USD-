import 'package:flutter/material.dart';

import '../core/settings.dart';

/// Design tokens.
///
/// Light theme (the default): white canvas, NoteLens green accent, soft
/// light-green cards, near-black text, pill buttons and large radii, in the
/// clean commerce-app style. Dark theme follows TikTok / Instagram dark mode: true-black canvas,
/// layered greys, white type, one vivid accent. Every text/background pair
/// keeps at least 4.5:1 contrast; high-contrast mode raises that further.
class AppTokens extends ThemeExtension<AppTokens> {
  final Color canvas;
  final Color card;
  final Color cardHigh;
  final Color line; // hairline dividers and card outlines
  final Color muted;
  final Color success;
  final Color warning;
  final Color danger;
  final Color shadow;
  final double radius;
  final double borderWidth;

  const AppTokens({
    required this.canvas,
    required this.card,
    required this.cardHigh,
    required this.line,
    required this.muted,
    required this.success,
    required this.warning,
    required this.danger,
    required this.shadow,
    this.radius = 28,
    this.borderWidth = 0,
  });

  /// Soft elevation used for cards in light mode (none in dark mode, where
  /// layers are separated by tone instead).
  List<BoxShadow> get elevation => shadow.a == 0
      ? const []
      : [
          BoxShadow(color: shadow, blurRadius: 24, offset: const Offset(0, 8)),
          BoxShadow(color: shadow, blurRadius: 2, offset: const Offset(0, 1)),
        ];

  @override
  AppTokens copyWith() => this;

  @override
  AppTokens lerp(AppTokens? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension TokensX on BuildContext {
  AppTokens get tokens => Theme.of(this).extension<AppTokens>()!;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

/// Second brand colour for gradients: the accent shifted around the hue
/// wheel, so gradients always match whatever accent the user picks.
Color accentPartner(Color accent) {
  final h = HSLColor.fromColor(accent);
  return h.withHue((h.hue + 40) % 360).withLightness((h.lightness * 0.85).clamp(0.3, 0.7)).toColor();
}

ThemeData buildTheme(AppSettings s, Brightness brightness) {
  final hc = s.highContrast;
  final dark = hc || brightness == Brightness.dark;
  final accent = hc ? const Color(0xFFFFD600) : Color(s.accentColor);
  final onAccent = ThemeData.estimateBrightnessForColor(accent) == Brightness.dark ? Colors.white : const Color(0xFF0B0D0C);
  final ink = dark ? Colors.white : const Color(0xFF101914);

  final tokens = AppTokens(
    canvas: hc ? Colors.black : (dark ? const Color(0xFF060708) : Colors.white),
    card: hc ? Colors.black : (dark ? const Color(0xFF121417) : Colors.white),
    // Light green tint of the accent: the "green cards".
    cardHigh: hc
        ? const Color(0xFF111111)
        : (dark ? const Color(0xFF1C1F24) : Color.alphaBlend(accent.withValues(alpha: 0.09), const Color(0xFFF6F8F7))),
    line: hc ? Colors.white : (dark ? const Color(0x1AFFFFFF) : const Color(0xFFE5EBE7)),
    muted: hc ? Colors.white : (dark ? const Color(0xFF9AA0A9) : const Color(0xFF5E6B63)),
    success: dark ? const Color(0xFF34D399) : const Color(0xFF1F9D63),
    warning: dark ? const Color(0xFFFBBF24) : const Color(0xFFB7791F),
    danger: dark ? const Color(0xFFFF6B6B) : const Color(0xFFD64545),
    shadow: dark ? const Color(0x00000000) : const Color(0x0D0B3D1E),
    borderWidth: hc ? 2 : 0,
  );

  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: dark ? Brightness.dark : Brightness.light).copyWith(
    primary: accent,
    onPrimary: onAccent,
    secondary: accentPartner(accent),
    surface: tokens.card,
    onSurface: ink,
    error: tokens.danger,
    outlineVariant: tokens.line,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: scheme.brightness,
    fontFamily: 'Inter',
    splashFactory: InkSparkle.splashFactory,
  );
  final t = base.textTheme.apply(bodyColor: ink, displayColor: ink);
  final text = t.copyWith(
    displayLarge: t.displayLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -2, height: 1.0),
    displayMedium: t.displayMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.6, height: 1.02),
    displaySmall: t.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.2, height: 1.06),
    headlineLarge: t.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
    headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
    headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
    titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
    titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.1),
    titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    bodyLarge: t.bodyLarge?.copyWith(height: 1.4),
    bodyMedium: t.bodyMedium?.copyWith(height: 1.4),
    labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0),
  );

  const pill = StadiumBorder();
  final hcSide = hc ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none;

  return base.copyWith(
    scaffoldBackgroundColor: tokens.canvas,
    textTheme: text,
    extensions: [tokens],
    dividerTheme: DividerThemeData(color: tokens.line, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.canvas,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(color: ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 58),
        shape: StadiumBorder(side: hcSide),
        textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 58),
        shape: pill,
        foregroundColor: ink,
        side: BorderSide(color: hc ? Colors.white : tokens.line, width: hc ? 2 : 1.5),
        textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: dark ? accent : ink,
        shape: pill,
        textStyle: text.labelLarge,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.cardHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: hcSide),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: dark ? accent : ink, width: 2),
      ),
      labelStyle: TextStyle(color: tokens.muted, fontWeight: FontWeight.w500),
      floatingLabelStyle: TextStyle(color: dark ? accent : ink, fontWeight: FontWeight.w600),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: StadiumBorder(side: hc ? const BorderSide(color: Colors.white) : BorderSide(color: tokens.line)),
      backgroundColor: tokens.card,
      selectedColor: dark ? accent : ink,
      labelStyle: text.labelLarge?.copyWith(color: ink),
      secondaryLabelStyle: text.labelLarge?.copyWith(color: dark ? onAccent : Colors.white),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      showCheckmark: false,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? onAccent : null),
      trackColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? accent : null),
      trackOutlineColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? accent : tokens.line),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: accent,
      thumbColor: accent,
      inactiveTrackColor: tokens.cardHigh,
      trackHeight: 6,
      overlayColor: accent.withValues(alpha: 0.12),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: dark ? accent : ink,
        selectedForegroundColor: dark ? onAccent : Colors.white,
        side: BorderSide(color: tokens.line),
        textStyle: text.labelLarge,
        minimumSize: const Size(0, 48),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tokens.card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: tokens.muted.withValues(alpha: 0.4),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    listTileTheme: ListTileThemeData(iconColor: ink, textColor: ink),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}
