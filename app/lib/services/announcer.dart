import 'dart:async';
import 'dart:ui';

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../core/settings.dart';

enum Buzz { light, success, warning, danger, pulse }

/// How important a message is. A message interrupts anything of the same or
/// lower priority; [low] messages are dropped while something is being said.
enum Priority { low, normal, high, urgent }

enum VoiceGender { female, male, unknown }

class TtsVoice {
  final String name;
  final String locale;
  final VoiceGender gender;
  final bool installed;
  const TtsVoice(this.name, this.locale, this.gender, this.installed);
}

/// Voice and haptic feedback, driven by [AppSettings]. When TalkBack or
/// VoiceOver is running, speech goes through it so two voices never overlap.
class Announcer {
  final AppSettings settings;
  final FlutterTts _tts = FlutterTts();
  bool screenReaderOn = false;
  String? _last;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _speaking = false;
  Priority _current = Priority.low;
  List<TtsVoice>? _voices;
  bool languageMissing = false;

  Announcer(this.settings) {
    settings.addListener(_apply);
  }

  bool get speaking => _speaking;

  Future<void> init() async {
    try {
      await _tts.awaitSpeakCompletion(false);
      _tts.setStartHandler(() => _speaking = true);
      _tts.setCompletionHandler(() => _speaking = false);
      _tts.setCancelHandler(() => _speaking = false);
      _tts.setErrorHandler((_) => _speaking = false);
    } catch (_) {}
    await _apply();
  }

  String? _appliedKey;

  /// TTS failures (no engine installed, voice missing) must never break scanning.
  Future<void> _apply() async {
    final key = '${settings.language}|${settings.voiceStyle}|${settings.voiceName}|${settings.speechRate}|${settings.pitch}';
    if (key == _appliedKey) return;
    _appliedKey = key;
    try {
      await _tts.setSpeechRate(settings.speechRate);
      final available = await _tts.isLanguageAvailable(settings.ttsLocale);
      languageMissing = available != true;
      await _tts.setLanguage(settings.ttsLocale);
      final voice = await pickVoice();
      if (voice != null) await _tts.setVoice({'name': voice.name, 'locale': voice.locale});
      await _tts.setPitch(effectivePitch(voice));
    } catch (_) {}
  }

  /// The pitch to use: the user's pitch, shaped by the voice style. When the
  /// phone has no voice of the wanted gender, pitch approximates it.
  double effectivePitch(TtsVoice? voice) {
    final p = settings.pitch;
    return switch (settings.voiceStyle) {
      VoiceStyle.young => (p * 1.3).clamp(0.5, 2.0),
      VoiceStyle.man => voice?.gender == VoiceGender.male ? p : (p * 0.75).clamp(0.5, 2.0),
      VoiceStyle.woman => voice?.gender == VoiceGender.female ? p : (p * 1.1).clamp(0.5, 2.0),
    };
  }

  /// Voices for the current language, installed ones first.
  Future<List<TtsVoice>> voices() async {
    _voices ??= await _loadVoices();
    final lang = settings.ttsLocale.split('-').first.toLowerCase();
    final list = [for (final v in _voices!) if (v.locale.toLowerCase().startsWith(lang)) v];
    list.sort((a, b) {
      if (a.installed != b.installed) return a.installed ? -1 : 1;
      final region = settings.ttsLocale.toLowerCase();
      final ar = a.locale.toLowerCase() == region, br = b.locale.toLowerCase() == region;
      return ar == br ? 0 : (ar ? -1 : 1);
    });
    return list;
  }

  Future<TtsVoice?> pickVoice() async {
    final list = await voices();
    if (list.isEmpty) return null;
    if (settings.voiceName != null) {
      for (final v in list) {
        if (v.name == settings.voiceName) return v;
      }
    }
    final want = settings.voiceStyle == VoiceStyle.man ? VoiceGender.male : VoiceGender.female;
    for (final v in list) {
      if (v.gender == want && v.installed) return v;
    }
    return list.first;
  }

  Future<List<TtsVoice>> _loadVoices() async {
    try {
      final raw = await _tts.getVoices as List?;
      return [
        for (final m in raw ?? const [])
          if (m is Map)
            TtsVoice(
              '${m['name']}',
              '${m['locale']}',
              voiceGender('${m['name']}', '${m['gender'] ?? ''} ${m['features'] ?? ''}'),
              !'${m['features'] ?? ''}'.contains('notInstalled'),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Opens the phone's text-to-speech settings, to download a voice.
  Future<void> openVoiceSettings() async {
    try {
      await const MethodChannel('notelens/system').invokeMethod('openTtsSettings');
    } catch (_) {}
  }

  /// Speaks [text] once with the given settings, for voice previews.
  Future<void> preview(String text) => say(text, priority: Priority.urgent, dedupe: Duration.zero, force: true);

  /// Identical text within [dedupe] is skipped.
  Future<void> say(String text,
      {Priority priority = Priority.normal,
      Duration dedupe = const Duration(seconds: 2),
      bool force = false}) async {
    if ((!settings.voiceEnabled && !force) || text.isEmpty) return;
    final now = DateTime.now();
    if (text == _last && now.difference(_lastAt) < dedupe) return;
    if (_speaking && priority.index < _current.index) return; // something more important is playing
    if (_speaking && priority == Priority.low) return;
    _last = text;
    _lastAt = now;
    _current = priority;
    final view = PlatformDispatcher.instance.implicitView;
    if (screenReaderOn && view != null) {
      await SemanticsService.sendAnnouncement(view, text, TextDirection.ltr);
      return;
    }
    try {
      await _apply();
      await _tts.stop();
      _speaking = true;
      await _tts.speak(text);
    } catch (_) {
      _speaking = false;
    }
  }

  Future<void> buzz(Buzz kind) async {
    if (!settings.haptics) return;
    switch (kind) {
      case Buzz.light:
        await HapticFeedback.selectionClick();
      case Buzz.pulse:
        await HapticFeedback.lightImpact();
      case Buzz.success:
        await HapticFeedback.mediumImpact();
      case Buzz.warning:
        await HapticFeedback.heavyImpact();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await HapticFeedback.heavyImpact();
      case Buzz.danger:
        for (var i = 0; i < 3; i++) {
          await HapticFeedback.heavyImpact();
          await Future<void>.delayed(const Duration(milliseconds: 90));
        }
    }
  }

  Future<void> stop() async {
    _speaking = false;
    try {
      await _tts.stop();
    } catch (_) {}
  }

  void dispose() {
    settings.removeListener(_apply);
    stop();
  }
}

/// Gender of a TTS voice. iOS reports it; Android does not, so Google's
/// voice codes are mapped by hand (e.g. "en-us-x-iom-local" is male).
VoiceGender voiceGender(String name, String extra) {
  final e = extra.toLowerCase();
  if (e.contains('female')) return VoiceGender.female;
  if (e.contains('male')) return VoiceGender.male; // "female" was handled above
  final m = RegExp(r'-x-([a-z]{3})').firstMatch(name.toLowerCase());
  final code = m?.group(1);
  if (code != null) {
    if (_googleMale.contains(code)) return VoiceGender.male;
    if (_googleFemale.contains(code)) return VoiceGender.female;
  }
  final n = name.toLowerCase();
  if (n.contains('female')) return VoiceGender.female;
  if (n.contains('#male') || n.endsWith('male')) return VoiceGender.male;
  return VoiceGender.unknown;
}

const _googleMale = {'iol', 'iom', 'tpd', 'gbb', 'gbd', 'rjs', 'end', 'aub', 'aud'};
const _googleFemale = {
  'sfg', 'iob', 'iog', 'tpc', 'tpf', 'gba', 'gbc', 'gbg', 'ahp', 'cxx', 'ena', 'aua', 'auc',
};
