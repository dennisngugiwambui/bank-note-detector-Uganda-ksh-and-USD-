import 'dart:ui';

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../core/settings.dart';

enum Buzz { light, success, warning, danger }

/// Voice and haptic feedback, driven by [AppSettings]. When a screen reader
/// (TalkBack or VoiceOver) is running, speech goes through it so the two
/// voices never overlap.
class Announcer {
  final AppSettings settings;
  final FlutterTts _tts = FlutterTts();
  bool screenReaderOn = false;
  String? _last;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  Announcer(this.settings) {
    settings.addListener(_apply);
  }

  Future<void> init() async {
    try {
      await _tts.awaitSpeakCompletion(false);
    } catch (_) {}
    await _apply();
  }

  /// TTS failures (no engine installed, voice missing) must never break scanning.
  Future<void> _apply() async {
    try {
      await _tts.setSpeechRate(settings.speechRate);
      await _tts.setPitch(settings.pitch);
      await _tts.setLanguage(settings.voiceLanguage); // the engine falls back to its default voice
    } catch (_) {}
  }

  /// Identical text within [dedupe] is skipped.
  Future<void> say(String text,
      {bool interrupt = true, Duration dedupe = const Duration(seconds: 2), bool force = false}) async {
    if (!settings.voiceEnabled && !force) return;
    final now = DateTime.now();
    if (text == _last && now.difference(_lastAt) < dedupe) return;
    _last = text;
    _lastAt = now;
    final view = PlatformDispatcher.instance.implicitView;
    if (screenReaderOn && view != null) {
      await SemanticsService.sendAnnouncement(view, text, TextDirection.ltr);
      return;
    }
    try {
      if (interrupt) await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> buzz(Buzz kind) async {
    if (!settings.haptics) return;
    switch (kind) {
      case Buzz.light:
        await HapticFeedback.selectionClick();
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
    try {
      await _tts.stop();
    } catch (_) {}
  }

  void dispose() {
    settings.removeListener(_apply);
    stop();
  }
}
