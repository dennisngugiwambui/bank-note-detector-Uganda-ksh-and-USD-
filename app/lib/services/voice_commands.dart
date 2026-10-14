import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum Command {
  scanMoney,
  objects,
  total,
  add,
  checkFake,
  repeat,
  light,
  teach,
  home,
  wallet,
  settings,
  activity,
  faster,
  slower,
  time,
  help,
  stop,
  guideOn,
  guideOff,
}

/// Keyword rules, English and Kiswahili. Order matters: the first rule with a
/// matching phrase wins, so specific phrases come before general ones.
const _rules = <(Command, List<String>)>[
  (Command.guideOff, ['voice guide off', 'turn off voice guide', 'zima mwongozo']),
  (Command.guideOn, ['voice guide on', 'turn on voice guide', 'washa mwongozo']),
  (Command.checkFake, ['fake', 'counterfeit', 'genuine', 'real or', 'bandia', 'feki', 'halali']),
  (Command.teach, ['teach', 'learn', 'fundisha', 'jifunze']),
  (Command.total, ['total', 'how much', 'count', 'jumla', 'ngapi pesa', 'pesa ngapi', 'hesabu']),
  (Command.add, ['add', 'ongeza', 'weka']),
  (Command.objects, [
    'in front', 'around', 'surround', 'object', 'obstacle', 'what is there', 'where am i', 'walk', 'describe',
    'mbele', 'karibu', 'mazingira', 'vitu', 'kitu', 'njia', 'tembea', 'eleza',
  ]),
  (Command.scanMoney, ['money', 'note', 'cash', 'coin', 'scan', 'read', 'pesa', 'noti', 'sarafu', 'soma', 'changanua']),
  (Command.repeat, ['repeat', 'again', 'say that', 'rudia', 'tena']),
  (Command.light, ['light', 'torch', 'flash', 'tochi', 'taa', 'mwanga']),
  (Command.wallet, ['wallet', 'pochi']),
  (Command.activity, ['activity', 'history', 'historia']),
  (Command.settings, ['setting', 'mipangilio']),
  (Command.home, ['home', 'nyumbani', 'mwanzo']),
  (Command.faster, ['faster', 'speed up', 'haraka']),
  (Command.slower, ['slower', 'slow down', 'polepole', 'pole pole']),
  (Command.time, ['time', 'saa ngapi', 'saa']),
  (Command.help, ['help', 'what can i say', 'commands', 'msaada', 'nisaidie']),
  (Command.stop, ['stop', 'quiet', 'cancel', 'shut up', 'simama', 'nyamaza', 'acha']),
];

/// Maps recognised speech to a command, or null.
Command? parseCommand(String heard) {
  final t = ' ${heard.toLowerCase().replaceAll(RegExp(r"[^a-z0-9' ]"), ' ').replaceAll(RegExp(r'\s+'), ' ').trim()} ';
  if (t.trim().isEmpty) return null;
  for (final (cmd, phrases) in _rules) {
    for (final p in phrases) {
      // Whole words only, so "add" does not match "address".
      if (t.contains(' $p ') || (p.contains(' ') && t.contains(p))) return cmd;
    }
  }
  return null;
}

/// Wraps speech_to_text: one utterance per [listen] call.
class VoiceCommands extends ChangeNotifier {
  final SpeechToText _stt = SpeechToText();
  bool _ready = false;
  bool available = true;
  bool listening = false;
  String heard = '';

  Future<bool> init() async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize(
        onStatus: (s) {
          final now = s == 'listening';
          if (now != listening) {
            listening = now;
            notifyListeners();
          }
        },
        onError: (_) {
          listening = false;
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('speech init: $e');
      _ready = false;
    }
    available = _ready;
    return _ready;
  }

  /// Listens for one command. Completes with the words heard ('' if nothing).
  Future<String> listen(String localeId) async {
    if (!await init()) return '';
    final done = Completer<String>();
    heard = '';
    listening = true;
    notifyListeners();
    try {
      await _stt.listen(
        localeId: localeId,
        listenFor: const Duration(seconds: 7),
        pauseFor: const Duration(seconds: 2),
        listenOptions: SpeechListenOptions(partialResults: true, cancelOnError: true),
        onResult: (SpeechRecognitionResult r) {
          heard = r.recognizedWords;
          notifyListeners();
          if (r.finalResult && !done.isCompleted) done.complete(heard);
        },
      );
    } catch (e) {
      debugPrint('speech listen: $e');
      if (!done.isCompleted) done.complete('');
    }
    // Some engines end without a final result.
    final result = await done.future.timeout(const Duration(seconds: 9), onTimeout: () => heard);
    listening = false;
    notifyListeners();
    return result;
  }

  Future<void> cancel() async {
    try {
      await _stt.cancel();
    } catch (_) {}
    listening = false;
    notifyListeners();
  }
}
