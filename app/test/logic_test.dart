import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:banknote_identifier/core/currency.dart';
import 'package:banknote_identifier/core/strings.dart';
import 'package:banknote_identifier/ml/currency_classifier.dart';
import 'package:banknote_identifier/ml/frame.dart';
import 'package:banknote_identifier/ml/object_detector.dart';
import 'package:banknote_identifier/ml/scene_classifier.dart';
import 'package:banknote_identifier/ml/scene_speech.dart';
import 'package:banknote_identifier/ml/scene_tracker.dart';
import 'package:banknote_identifier/services/announcer.dart';
import 'package:banknote_identifier/services/voice_commands.dart';
import 'package:flutter_test/flutter_test.dart';

Tracked _obj(String label, {double bearing = 0, double? distance, Hazard hazard = Hazard.none}) {
  const box = Detection('x', 0.9, 0.4, 0.4, 0.6, 0.6);
  return Tracked(0, label, 0.9, box, box, 0)
    ..bearing = bearing
    ..distance = distance
    ..hazard = hazard;
}

void main() {
  group('Note', () {
    test('parses unified labels and speaks them', () {
      expect(Note.parse('KES_100')!.spoken, '100 Kenyan shillings');
      expect(Note.parse('USD_1')!.spoken, '1 US dollar');
      expect(Note.parse('USD_20_front')!.label, 'USD_20');
      expect(Note.parse('background'), isNull);
      expect(Note.parse('INR_abc'), isNull);
    });

    test('coins and cents', () {
      final c = Note.parse('KES_20_coin')!;
      expect(c.coin, isTrue);
      expect(c.label, 'KES_20_coin');
      expect(c.spoken, '20 Kenyan shillings coin');
      final q = Note.parse('USD_25c_coin')!;
      expect(q.value, 0.25);
      expect(q.label, 'USD_25c_coin');
      expect(q.spoken, '25 cent coin');
      expect(formatAmount('USD', 0.25), r'$ 0.25');
      expect(formatAmount('KES', 1500), 'KSh 1,500');
    });

    test('Kiswahili names', () {
      expect(Note.parse('KES_100')!.spokenIn(const S('sw')), 'shilingi za Kenya 100');
      expect(Note.parse('KES_5_coin')!.spokenIn(const S('sw')), 'sarafu ya shilingi za Kenya 5');
    });
  });

  group('PredictionSmoother', () {
    test('announces once after enough agreeing frames', () {
      final s = PredictionSmoother(threshold: 0.8, window: 7, minVotes: 5);
      final results = [for (var i = 0; i < 6; i++) s.add(const Prediction('UGX_5000', 0.95))];
      expect(results.whereType<Note>().length, 1);
      expect(results[4]!.label, 'UGX_5000'); // 5th vote triggers
    });

    test('low-confidence frames never announce', () {
      final s = PredictionSmoother(threshold: 0.8);
      for (var i = 0; i < 20; i++) {
        expect(s.add(const Prediction('INR_500', 0.6)), isNull);
      }
    });

    test('re-arms after the note leaves the view', () {
      final s = PredictionSmoother(threshold: 0.8, window: 7, minVotes: 5);
      Note? last;
      for (var i = 0; i < 7; i++) {
        last = s.add(const Prediction('KES_50', 0.9)) ?? last;
      }
      expect(last?.label, 'KES_50');
      for (var i = 0; i < 7; i++) {
        s.add(const Prediction(backgroundLabel, 0.95));
      }
      final again = [for (var i = 0; i < 7; i++) s.add(const Prediction('KES_50', 0.9))];
      expect(again.whereType<Note>().length, 1);
    });

    test('objects-mode smoother is stricter', () {
      final s = PredictionSmoother.background(0.85);
      expect(s.threshold, greaterThanOrEqualTo(0.92));
      for (var i = 0; i < 10; i++) {
        expect(s.add(const Prediction('KES_100', 0.9)), isNull);
      }
    });
  });

  group('taught notes', () {
    test('nearest neighbours with a margin', () {
      final ex = {
        'KES_100': [
          [1.0, 0.0, 0.0],
          [0.9, 0.1, 0.0],
        ],
        'KES_50': [
          [0.0, 1.0, 0.0],
        ],
      };
      expect(TaughtNotes.matchIn(ex, [1.0, 0.05, 0.0])?.$1, 'KES_100');
      expect(TaughtNotes.matchIn(ex, [0.0, 0.0, 1.0]), isNull); // like nothing taught
      expect(TaughtNotes.matchIn(ex, [0.7, 0.7, 0.0]), isNull); // ambiguous
    });
  });

  group('scene tracker', () {
    test('accelerometer pose', () {
      final upright = DevicePose.fromAccel(0, 9.8, 0);
      expect(upright.quarter, 0);
      expect(upright.pitchDown, closeTo(0, 0.01));
      expect(DevicePose.fromAccel(0, 0, 9.8).lookingDown, isTrue);
      expect(DevicePose.fromAccel(9.8, 0, 0).quarter, 1);
      expect(DevicePose.fromAccel(-9.8, 0, 0).quarter, 3);
    });

    test('an approaching car ahead is a danger before it is close', () {
      final tracker = SceneTracker();
      List<Tracked> seen = const [];
      for (var i = 0; i < 6; i++) {
        final t = i * 0.2;
        final h = 0.12 * math.exp(0.5 * t); // box height grows 50% per second: ~2 s to contact
        seen = tracker.update([Detection('car', 0.8, 0.42, 0.5 - h / 2, 0.58, 0.5 + h / 2)], t, DevicePose.upright, 0.75);
      }
      final car = seen.single;
      expect(car.ttc, closeTo(2, 0.3));
      expect(car.distance, greaterThan(3)); // still several metres away
      expect(car.hazard, Hazard.danger);
      expect(car.bearing.abs(), lessThan(6));
    });

    test('a still chair far away is not a hazard; close in the path it is', () {
      final tracker = SceneTracker(warnDistance: 3.5);
      List<Tracked> seen = const [];
      for (var i = 0; i < 3; i++) {
        seen = tracker.update([const Detection('chair', 0.8, 0.45, 0.45, 0.55, 0.55)], i * 0.2, DevicePose.upright, 0.75);
      }
      expect(seen.single.distance, greaterThan(3.5));
      expect(seen.single.hazard, Hazard.none);
      final near = SceneTracker(warnDistance: 3.5);
      for (var i = 0; i < 3; i++) {
        seen = near.update([const Detection('chair', 0.8, 0.3, 0.3, 0.7, 0.9)], i * 0.2, DevicePose.upright, 0.75);
      }
      expect(seen.single.distance, lessThan(3.5));
      expect(seen.single.inPath, isTrue);
      expect(seen.single.hazard, isNot(Hazard.none));
    });

    test('nothing is a hazard while the camera looks at the floor', () {
      final tracker = SceneTracker();
      List<Tracked> seen = const [];
      for (var i = 0; i < 3; i++) {
        seen = tracker.update(
            [const Detection('dining table', 0.9, 0, 0, 1, 1)], i * 0.2, const DevicePose(70, 0), 0.75);
      }
      expect(seen.single.hazard, Hazard.none);
    });

    test('left and right follow how the phone is held', () {
      // Phone turned with its top to the left: the top of the camera frame is the user's left.
      final tracker = SceneTracker();
      List<Tracked> seen = const [];
      for (var i = 0; i < 2; i++) {
        seen = tracker.update(
            [const Detection('person', 0.9, 0.4, 0.05, 0.6, 0.2)], i * 0.2, const DevicePose(0, 1), 0.75);
      }
      expect(seen.single.bearing, lessThan(-15));
    });

    test('one weak detection is not announced', () {
      final tracker = SceneTracker();
      final seen = tracker.update([const Detection('knife', 0.55, 0.4, 0.4, 0.6, 0.6)], 0, DevicePose.upright, 0.75);
      expect(seen, isEmpty);
    });
  });

  group('scene speech', () {
    test('English and Kiswahili sentences', () {
      const en = SceneSpeech(S('en'));
      expect(en.describe([_obj('car', bearing: -20, distance: 5)]), 'Car on your left, 5 metres');
      expect(en.describe([_obj('person', distance: 2), _obj('person', distance: 3)]), '2 people ahead, 2 metres');
      expect(en.describe([], sceneGuess: 'shoes'), 'Looks like shoes');
      expect(en.describe([]), 'Nothing recognized');
      expect(en.alert(_obj('person', distance: 0.8, hazard: Hazard.danger)), 'Stop! Person ahead, very close.');
      const sw = SceneSpeech(S('sw'));
      expect(sw.describe([_obj('car', bearing: -20, distance: 5)]), 'Gari kushoto kwako, mita 5');
    });

    test('clock directions and steps', () {
      const clock = SceneSpeech(S('en'), direction: DirectionStyle.clock, unit: DistanceUnit.steps);
      expect(clock.where(30), "at 1 o'clock");
      expect(clock.where(-60), "at 10 o'clock");
      expect(clock.where(0), "at 12 o'clock");
      expect(clock.howFar(2.1), '3 steps');
    });
  });

  group('voice', () {
    test('commands in English and Kiswahili', () {
      expect(parseCommand('scan money'), Command.scanMoney);
      expect(parseCommand('What is in front of me?'), Command.objects);
      expect(parseCommand('read my total'), Command.total);
      expect(parseCommand('teach a note'), Command.teach);
      expect(parseCommand('is this fake'), Command.checkFake);
      expect(parseCommand('turn on the light'), Command.light);
      expect(parseCommand('what time is it'), Command.time);
      expect(parseCommand('voice guide off'), Command.guideOff);
      expect(parseCommand('soma pesa'), Command.scanMoney);
      expect(parseCommand('nini kiko mbele yangu'), Command.objects);
      expect(parseCommand('saa ngapi'), Command.time);
      expect(parseCommand('jumla yangu'), Command.total);
      expect(parseCommand('address'), isNull); // whole words only
      expect(parseCommand(''), isNull);
    });

    test('voice gender from Google voice codes', () {
      expect(voiceGender('en-us-x-iom-local', ''), VoiceGender.male);
      expect(voiceGender('en-us-x-sfg-local', ''), VoiceGender.female);
      expect(voiceGender('Samantha', 'female'), VoiceGender.female);
      expect(voiceGender('Daniel', 'male'), VoiceGender.male);
      expect(voiceGender('sw-ke-x-abc-network', ''), VoiceGender.unknown);
    });

    test('time in English and Swahili time', () {
      expect(const S('en').timeNow(14, 5), 'It is 2:05 PM.');
      expect(const S('sw').timeNow(7, 0), 'Ni saa 1 asubuhi.'); // Swahili hours start at 6 am
    });
  });

  group('frameToInput', () {
    // 4x2 BGRA frame: left half red, right half blue.
    FrameData bgraFrame(int rotation) {
      final px = Uint8List(4 * 2 * 4);
      for (var y = 0; y < 2; y++) {
        for (var x = 0; x < 4; x++) {
          final i = (y * 4 + x) * 4;
          if (x < 2) {
            px[i + 2] = 255; // R
          } else {
            px[i] = 255; // B
          }
          px[i + 3] = 255;
        }
      }
      return FrameData(4, 2, rotation, true, [px], [16], [4]);
    }

    test('letterboxes a landscape frame with black bars top and bottom', () {
      final out = frameToInput(bgraFrame(0), 8);
      // 4x2 scaled to 8x4, centred: rows 0-1 and 6-7 are padding.
      expect(out.rgb.sublist(0, 3), [0, 0, 0]);
      const mid = (3 * 8 + 0) * 3;
      expect(out.rgb.sublist(mid, mid + 3), [255, 0, 0]); // red on the left
      const right = (3 * 8 + 7) * 3;
      expect(out.rgb.sublist(right, right + 3), [0, 0, 255]);
    });

    test('rotation 90 puts the sensor-left side on top', () {
      final out = frameToInput(bgraFrame(90), 8);
      // Upright frame is 2 wide x 4 tall; scaled 4x8, columns 2..5.
      const top = (0 * 8 + 3) * 3;
      const bottom = (7 * 8 + 3) * 3;
      expect(out.rgb.sublist(top, top + 3), [255, 0, 0]);
      expect(out.rgb.sublist(bottom, bottom + 3), [0, 0, 255]);
      expect(out.rgb.sublist(0, 3), [0, 0, 0]); // left padding
    });

    test('YUV420 grey converts to grey', () {
      const w = 4;
      const h = 4;
      final y = Uint8List(w * h)..fillRange(0, w * h, 128);
      final u = Uint8List(4)..fillRange(0, 4, 128);
      final v = Uint8List(4)..fillRange(0, 4, 128);
      final f = FrameData(w, h, 0, false, [y, u, v], [w, 2, 2], [1, 1, 1]);
      final out = frameToInput(f, 4);
      expect(out.rgb.every((b) => b == 128), isTrue);
      expect(out.brightness, closeTo(128, 0.5));
    });
  });

  group('objects mode models', () {
    test('detector output layout: post-processed accepted, raw anchors rejected', () {
      // EfficientDet-Lite2 with TFLite_Detection_PostProcess (bundled)
      expect(ObjectDetector.hasPostProcessOutputs([[1, 25, 4], [1, 25], [1, 25], [1]]), isTrue);
      // MediaPipe build: raw anchors, the cause of "Nothing recognized" on every frame
      expect(ObjectDetector.hasPostProcessOutputs([[1, 19206, 90], [1, 19206, 4]]), isFalse);
    });

    test('bundled detector labels are COCO and every scene group label exists', () {
      final det = File('assets/detector/labels.txt').readAsLinesSync();
      expect(det.first.trim(), 'person');
      expect(det, containsAll(['laptop', 'keyboard', 'bottle', 'chair', 'car']));
      final lines = File('assets/scene/labels.txt').readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
      expect(lines.length, 1000); // one per model output ("crane" and "maillot" appear twice)
      final imagenet = lines.map((l) => l.trim()).toSet();
      final missing = imagenetGroups.keys.where((k) => !imagenet.contains(k)).toList();
      expect(missing, isEmpty);
      expect(spokenName('space bar'), 'keyboard');
      expect(spokenName('running shoe'), 'shoes');
    });
  });
}
