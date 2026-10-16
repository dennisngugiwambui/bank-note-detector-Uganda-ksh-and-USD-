import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ml/scene_speech.dart';
import 'strings.dart';

enum VoiceStyle { woman, man, young }

/// All user-configurable behaviour, persisted on device. Widgets rebuild
/// through ChangeNotifier. To add a setting, add a field, a key in [_read],
/// and a line in [_save].
class AppSettings extends ChangeNotifier {
  final SharedPreferences _prefs;
  AppSettings._(this._prefs);

  static Future<AppSettings> load() async {
    final s = AppSettings._(await SharedPreferences.getInstance());
    s._read();
    return s;
  }

  // Appearance
  ThemeMode themeMode = ThemeMode.light;
  int accentColor = accentChoices.first.toARGB32();
  bool highContrast = false;
  double textScale = 1.0;

  // Language and voice
  String language = 'en'; // a key of appLanguages
  VoiceStyle voiceStyle = VoiceStyle.woman;
  String? voiceName; // a specific TTS voice; null = pick from [voiceStyle]
  bool voiceEnabled = true;
  double speechRate = 0.5; // flutter_tts: 0..1
  double pitch = 1.0; // 0.5..2, on top of the voice style
  bool haptics = true;
  bool announceTotals = true;

  // Accessibility
  /// Built-in screen reader: touch to hear, double tap to activate. Ignored
  /// while TalkBack or VoiceOver is on. Off unless the user asks for it on the
  /// first screen, because it replaces normal taps and swipes.
  bool voiceGuide = false;
  bool listenOnOpen = false; // start a voice command whenever the app opens
  bool showAlertBanners = false; // visual pop-ups; voice and vibration always happen

  // Detection
  /// Minimum calibrated confidence for announcing a note. Higher = fewer
  /// mistakes, slower answers. Set it from training/evaluate_tflite.py.
  double sensitivity = 0.9; // 98% per-frame precision on held-out photos (training/export_v2.log)
  bool autoTorch = true;
  bool notesInObjectsMode = true; // also announce money while describing surroundings
  Set<String> enabledCurrencies = {'INR', 'KES', 'EGP', 'UGX', 'USD'};

  // Surroundings (Objects mode)
  bool obstacleAlerts = true;
  double warnDistance = 3.5; // metres
  bool proximityVibration = true; // vibrates faster as an obstacle in the path gets closer
  DistanceUnit distanceUnit = DistanceUnit.metres;
  DirectionStyle directionStyle = DirectionStyle.simple;

  // Money
  bool noteFeatures = true; // say the colour and animal after the value

  // Authenticity
  bool uvLampAvailable = false;
  bool backlightStep = true;

  // Lifecycle
  bool onboardingDone = false;
  bool guideIntroduced = false; // the voice guide's gestures were explained once

  S get strings => S(language);
  String get ttsLocale => appLanguages[language]?.$2 ?? 'en-US';
  String get speechLocale => appLanguages[language]?.$3 ?? 'en_US';

  static const accentChoices = <Color>[
    Color(0xFF15803D), // NoteLens green: 5:1 against white
    Color(0xFFC6F24E), // lime
    Color(0xFF8B7CF6), // violet
    Color(0xFF4ADE80), // mint
    Color(0xFFFF8A4C), // tangerine
    Color(0xFF38BDF8), // sky
    Color(0xFFFFD600), // high-visibility yellow
  ];

  void _read() {
    final p = _prefs;
    themeMode = ThemeMode.values[p.getInt('themeMode2') ?? themeMode.index];
    accentColor = p.getInt('accentColor2') ?? accentColor;
    highContrast = p.getBool('highContrast') ?? highContrast;
    textScale = p.getDouble('textScale') ?? textScale;
    language = p.getString('language') ?? language;
    if (!appLanguages.containsKey(language)) language = 'en';
    voiceStyle = VoiceStyle.values[(p.getInt('voiceStyle') ?? voiceStyle.index).clamp(0, VoiceStyle.values.length - 1)];
    voiceName = p.getString('voiceName');
    voiceEnabled = p.getBool('voiceEnabled') ?? voiceEnabled;
    speechRate = p.getDouble('speechRate') ?? speechRate;
    pitch = p.getDouble('pitch') ?? pitch;
    haptics = p.getBool('haptics') ?? haptics;
    announceTotals = p.getBool('announceTotals') ?? announceTotals;
    // New key: 0.4/0.5 turned the guide on for everyone, which blocked normal touch.
    voiceGuide = p.getBool('voiceGuide2') ?? voiceGuide;
    listenOnOpen = p.getBool('listenOnOpen') ?? listenOnOpen;
    showAlertBanners = p.getBool('showAlertBanners') ?? showAlertBanners;
    sensitivity = p.getDouble('sensitivity') ?? sensitivity;
    autoTorch = p.getBool('autoTorch') ?? autoTorch;
    notesInObjectsMode = p.getBool('notesInObjectsMode') ?? notesInObjectsMode;
    enabledCurrencies = (p.getStringList('enabledCurrencies') ?? enabledCurrencies.toList()).toSet();
    obstacleAlerts = p.getBool('obstacleAlerts') ?? obstacleAlerts;
    warnDistance = p.getDouble('warnDistance') ?? warnDistance;
    proximityVibration = p.getBool('proximityVibration') ?? proximityVibration;
    distanceUnit = DistanceUnit.values[(p.getInt('distanceUnit') ?? distanceUnit.index).clamp(0, 2)];
    directionStyle = DirectionStyle.values[(p.getInt('directionStyle') ?? directionStyle.index).clamp(0, 1)];
    noteFeatures = p.getBool('noteFeatures') ?? noteFeatures;
    uvLampAvailable = p.getBool('uvLampAvailable') ?? uvLampAvailable;
    backlightStep = p.getBool('backlightStep') ?? backlightStep;
    onboardingDone = p.getBool('onboardingDone') ?? onboardingDone;
    guideIntroduced = p.getBool('guideIntroduced') ?? guideIntroduced;
  }

  void _save(void Function() change) {
    change();
    final p = _prefs;
    p.setInt('themeMode2', themeMode.index);
    p.setInt('accentColor2', accentColor);
    p.setBool('highContrast', highContrast);
    p.setDouble('textScale', textScale);
    p.setString('language', language);
    p.setInt('voiceStyle', voiceStyle.index);
    final v = voiceName;
    v == null ? p.remove('voiceName') : p.setString('voiceName', v);
    p.setBool('voiceEnabled', voiceEnabled);
    p.setDouble('speechRate', speechRate);
    p.setDouble('pitch', pitch);
    p.setBool('haptics', haptics);
    p.setBool('announceTotals', announceTotals);
    p.setBool('voiceGuide2', voiceGuide);
    p.setBool('listenOnOpen', listenOnOpen);
    p.setBool('showAlertBanners', showAlertBanners);
    p.setDouble('sensitivity', sensitivity);
    p.setBool('autoTorch', autoTorch);
    p.setBool('notesInObjectsMode', notesInObjectsMode);
    p.setStringList('enabledCurrencies', enabledCurrencies.toList());
    p.setBool('obstacleAlerts', obstacleAlerts);
    p.setDouble('warnDistance', warnDistance);
    p.setBool('proximityVibration', proximityVibration);
    p.setInt('distanceUnit', distanceUnit.index);
    p.setInt('directionStyle', directionStyle.index);
    p.setBool('noteFeatures', noteFeatures);
    p.setBool('uvLampAvailable', uvLampAvailable);
    p.setBool('backlightStep', backlightStep);
    p.setBool('onboardingDone', onboardingDone);
    p.setBool('guideIntroduced', guideIntroduced);
    notifyListeners();
  }

  void update(void Function(AppSettings s) change) => _save(() => change(this));
}
