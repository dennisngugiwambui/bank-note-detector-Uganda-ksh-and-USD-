import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// All user-configurable behaviour, persisted on device. Widgets rebuild
/// through ChangeNotifier. To add a setting, add a field, a key in [load],
/// and a setter that calls [_save].
class AppSettings extends ChangeNotifier {
  final SharedPreferences _prefs;
  AppSettings._(this._prefs);

  static Future<AppSettings> load() async {
    final s = AppSettings._(await SharedPreferences.getInstance());
    s._read();
    return s;
  }

  // Appearance
  ThemeMode themeMode = ThemeMode.dark;
  int accentColor = accentChoices.first.toARGB32();
  bool highContrast = false;
  double textScale = 1.0;

  // Voice and feedback
  bool voiceEnabled = true;
  double speechRate = 0.5; // flutter_tts: 0..1
  double pitch = 1.0; // 0.5..2
  String voiceLanguage = 'en-US';
  bool haptics = true;
  bool announceTotals = true;

  // Detection
  /// Minimum calibrated confidence for announcing a note. Higher = fewer
  /// mistakes, slower answers. Set it from training/evaluate_tflite.py.
  double sensitivity = 0.85;
  bool autoTorch = true;
  Set<String> enabledCurrencies = {'INR', 'KES', 'EGP', 'UGX', 'USD'};

  // Safety alerts (Objects mode)
  bool obstacleAlerts = true;
  /// Box area (fraction of frame) at which an object counts as close.
  double obstacleCloseness = 0.25;

  // Authenticity
  bool uvLampAvailable = false;
  bool backlightStep = true;

  // Lifecycle
  bool onboardingDone = false;

  static const accentChoices = <Color>[
    Color(0xFFC6F24E), // lime
    Color(0xFF8B7CF6), // violet
    Color(0xFF4ADE80), // mint
    Color(0xFFFF8A4C), // tangerine
    Color(0xFF38BDF8), // sky
    Color(0xFFFFD600), // high-visibility yellow
  ];

  static const voiceLanguages = <String, String>{
    'en-US': 'English (US)',
    'en-GB': 'English (UK)',
    'en-IN': 'English (India)',
    'en-KE': 'English (Kenya)',
    'en-NG': 'English (Nigeria)',
  };

  void _read() {
    final p = _prefs;
    themeMode = ThemeMode.values[p.getInt('themeMode') ?? ThemeMode.dark.index];
    accentColor = p.getInt('accentColor') ?? accentColor;
    highContrast = p.getBool('highContrast') ?? highContrast;
    textScale = p.getDouble('textScale') ?? textScale;
    voiceEnabled = p.getBool('voiceEnabled') ?? voiceEnabled;
    speechRate = p.getDouble('speechRate') ?? speechRate;
    pitch = p.getDouble('pitch') ?? pitch;
    voiceLanguage = p.getString('voiceLanguage') ?? voiceLanguage;
    haptics = p.getBool('haptics') ?? haptics;
    announceTotals = p.getBool('announceTotals') ?? announceTotals;
    sensitivity = p.getDouble('sensitivity') ?? sensitivity;
    autoTorch = p.getBool('autoTorch') ?? autoTorch;
    enabledCurrencies = (p.getStringList('enabledCurrencies') ?? enabledCurrencies.toList()).toSet();
    obstacleAlerts = p.getBool('obstacleAlerts') ?? obstacleAlerts;
    obstacleCloseness = p.getDouble('obstacleCloseness') ?? obstacleCloseness;
    uvLampAvailable = p.getBool('uvLampAvailable') ?? uvLampAvailable;
    backlightStep = p.getBool('backlightStep') ?? backlightStep;
    onboardingDone = p.getBool('onboardingDone') ?? onboardingDone;
  }

  void _save(void Function() change) {
    change();
    final p = _prefs;
    p.setInt('themeMode', themeMode.index);
    p.setInt('accentColor', accentColor);
    p.setBool('highContrast', highContrast);
    p.setDouble('textScale', textScale);
    p.setBool('voiceEnabled', voiceEnabled);
    p.setDouble('speechRate', speechRate);
    p.setDouble('pitch', pitch);
    p.setString('voiceLanguage', voiceLanguage);
    p.setBool('haptics', haptics);
    p.setBool('announceTotals', announceTotals);
    p.setDouble('sensitivity', sensitivity);
    p.setBool('autoTorch', autoTorch);
    p.setStringList('enabledCurrencies', enabledCurrencies.toList());
    p.setBool('obstacleAlerts', obstacleAlerts);
    p.setDouble('obstacleCloseness', obstacleCloseness);
    p.setBool('uvLampAvailable', uvLampAvailable);
    p.setBool('backlightStep', backlightStep);
    p.setBool('onboardingDone', onboardingDone);
    notifyListeners();
  }

  void update(void Function(AppSettings s) change) => _save(() => change(this));
}
