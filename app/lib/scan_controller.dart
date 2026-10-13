import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'core/activity.dart';
import 'core/currency.dart';
import 'core/settings.dart';
import 'ml/authenticity_checker.dart';
import 'ml/currency_classifier.dart';
import 'ml/frame.dart';
import 'ml/object_detector.dart';
import 'ml/scene_classifier.dart';
import 'services/announcer.dart';

enum ScanMode { currency, scene }

enum AuthPhase { idle, instructing, capturing, analysing, done }

// Top-level, so compute() can send it to a background isolate.
ModelInput _prepLetterbox((FrameData, int) a) => frameToInput(a.$1, a.$2);
ModelInput _prepStretch((FrameData, int) a) => frameToInput(a.$1, a.$2, letterbox: false);

/// All scanning logic, with no widgets: camera, models, smoothing,
/// announcements, safety alerts and the guided authenticity check. Screens
/// listen through ChangeNotifier.
class ScanController extends ChangeNotifier {
  static const darkLuma = 40.0;
  static const minSharpness = 25.0;
  static const currencyInterval = Duration(milliseconds: 150);
  static const sceneInterval = Duration(milliseconds: 600);
  static const _hazards = {
    'person', 'bicycle', 'car', 'motorcycle', 'bus', 'truck', 'train', 'dog', 'horse', 'cow',
    'chair', 'bench', 'couch', 'dining table', 'potted plant', 'fire hydrant', 'stop sign', 'traffic light',
  };

  final AppSettings settings;
  final ActivityStore activity;
  final Announcer announcer;
  final PredictionSmoother smoother = PredictionSmoother();

  ScanController({required this.settings, required this.activity}) : announcer = Announcer(settings);

  CameraController? camera;
  CurrencyClassifier? _classifier;
  ObjectDetector? _detector;
  SceneClassifier? _scene;
  AuthenticityChecker? authenticity;
  bool modelsLoaded = false;

  ScanMode mode = ScanMode.currency;
  String status = 'Ready';
  String? hint;
  Note? lastNote;
  double lastConfidence = 0;
  List<Detection> detections = const [];
  String? sceneGuess; // ImageNet fallback, e.g. "shoes"
  double sceneGuessScore = 0;
  bool torchOn = false;

  // Authenticity flow state, shown by the UI
  AuthPhase authPhase = AuthPhase.idle;
  List<AuthStep> authSteps = const [];
  int authStepIndex = 0;
  final List<StepResult> authResults = [];
  Verdict? verdict;
  Note? authNote;

  bool _busy = false;
  bool _torchAuto = false;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastHint = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastScene = '';
  DateTime _lastSceneAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<String, DateTime> _lastAlert = {};

  bool get hasCurrencyModel => _classifier != null;
  bool get hasDetector => _detector != null;
  bool get hasSceneClassifier => _scene != null;
  bool get authRunning => authPhase != AuthPhase.idle && authPhase != AuthPhase.done;

  Future<void> loadModels() async {
    if (modelsLoaded) return;
    await announcer.init();
    final loaded = await Future.wait<Object?>([
      CurrencyClassifier.load(),
      ObjectDetector.load(),
      AuthenticityChecker.load(),
      SceneClassifier.load(),
    ]);
    _classifier = loaded[0] as CurrencyClassifier?;
    _detector = loaded[1] as ObjectDetector?;
    authenticity = loaded[2] as AuthenticityChecker;
    _scene = loaded[3] as SceneClassifier?;
    modelsLoaded = true;
    notifyListeners();
  }

  // ---------------------------------------------------------------- camera

  Future<void> startCamera() async {
    if (camera != null) return;
    await loadModels();
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final c = CameraController(back, ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888);
      await c.initialize();
      await c.lockCaptureOrientation();
      camera = c;
      await c.startImageStream(_onFrame);
      await WakelockPlus.enable();
      if (!hasCurrencyModel && mode == ScanMode.currency) {
        _setStatus('Currency model not installed', speak: true);
      } else {
        _setStatus(mode == ScanMode.currency ? 'Point the camera at a banknote' : 'Describing your surroundings',
            speak: true);
      }
    } on CameraException catch (e) {
      _setStatus('Camera unavailable: ${e.description ?? e.code}', speak: true);
    }
  }

  Future<void> stopCamera() async {
    final c = camera;
    camera = null;
    torchOn = false;
    _torchAuto = false;
    await WakelockPlus.disable();
    if (c != null) {
      try {
        if (c.value.isStreamingImages) await c.stopImageStream();
      } catch (_) {}
      await c.dispose();
    }
    notifyListeners();
  }

  int get _rotation => camera?.description.sensorOrientation ?? 90;

  Future<void> _onFrame(CameraImage image) async {
    final now = DateTime.now();
    final interval = mode == ScanMode.currency ? currencyInterval : sceneInterval;
    if (_busy || authRunning || now.difference(_lastFrame) < interval) return;
    _busy = true;
    _lastFrame = now;
    try {
      final frame = FrameData.fromCamera(image, _rotation);
      if (mode == ScanMode.currency) {
        await _handleCurrency(frame);
      } else {
        await _handleScene(frame);
      }
    } catch (e) {
      debugPrint('frame error: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _handleCurrency(FrameData frame) async {
    final classifier = _classifier;
    if (classifier == null) return;
    final input = await compute(_prepLetterbox, (frame, classifier.inputSize));
    if (input.brightness < darkLuma) {
      if (settings.autoTorch && !torchOn) {
        _torchAuto = true;
        await setTorch(true, announce: false);
        _hint('Low light. Turning the light on.');
      } else {
        _hint('Too dark. Move to better light.');
      }
      return;
    }
    if (input.sharpness < minSharpness) {
      _hint('Hold steady', speak: false);
      return;
    }
    hint = null;
    smoother.threshold = settings.sensitivity;
    var p = await classifier.classify(input.rgb);
    final parsed = Note.parse(p.label);
    if (parsed != null && !settings.enabledCurrencies.contains(parsed.currency)) {
      p = Prediction(backgroundLabel, p.confidence); // currency switched off in settings
    }
    lastConfidence = p.confidence;
    final note = smoother.add(p);
    if (note != null) {
      lastNote = note;
      announcer.buzz(Buzz.success);
      _setStatus(note.spoken, speak: true);
      activity.add(ActivityEvent(
          kind: ActivityKind.note,
          severity: Severity.success,
          title: formatAmount(note.currency, note.value),
          detail: '${note.spoken} · ${(p.confidence * 100).round()}% confidence'));
    } else if (p.label == backgroundLabel && p.confidence > 0.8 && status != 'No note in view') {
      _setStatus('No note in view');
    } else {
      notifyListeners(); // live confidence gauge
    }
  }

  Future<void> _handleScene(FrameData frame) async {
    final detector = _detector;
    if (detector == null) {
      _hint('Object model not installed');
      return;
    }
    final input = await compute(_prepStretch, (frame, detector.inputWidth));
    detections = await detector.detect(input.rgb);
    if (settings.obstacleAlerts) _checkObstacles(detections);
    final scene = _scene;
    if (scene != null) {
      final small = await compute(_prepStretch, (frame, scene.inputSize));
      final guess = await scene.classify(small.rgb);
      sceneGuess = guess?.$1;
      sceneGuessScore = guess?.$2 ?? 0;
    }
    final text = describeScene(detections, sceneGuess: sceneGuess);
    final now = DateTime.now();
    final changed = text != _lastScene;
    final repeatDue = now.difference(_lastSceneAt) > const Duration(seconds: 6);
    if (changed || (repeatDue && text != nothingRecognized)) {
      _lastScene = text;
      _lastSceneAt = now;
      _setStatus(text, speak: true);
    } else {
      notifyListeners();
    }
  }

  /// Warns about hazards that are large (close) and in the walking path.
  void _checkObstacles(List<Detection> found) {
    final now = DateTime.now();
    for (final d in found) {
      if (!_hazards.contains(d.label)) continue;
      final inPath = d.centerX > 0.25 && d.centerX < 0.75;
      if (!inPath || d.area < settings.obstacleCloseness) continue;
      final last = _lastAlert[d.label];
      if (last != null && now.difference(last) < const Duration(seconds: 5)) continue;
      _lastAlert[d.label] = now;
      final veryClose = d.area > settings.obstacleCloseness * 1.8;
      final msg = 'Caution. ${d.label} ahead${veryClose ? ', very close' : ''}.';
      announcer.buzz(veryClose ? Buzz.danger : Buzz.warning);
      announcer.say(msg);
      activity.add(
          ActivityEvent(
              kind: ActivityKind.obstacle,
              severity: veryClose ? Severity.danger : Severity.warning,
              title: '${d.label[0].toUpperCase()}${d.label.substring(1)} ahead',
              detail: veryClose ? 'Very close, in your path' : 'In your path'),
          popUp: true);
      break; // one alert at a time
    }
  }

  // ---------------------------------------------------------------- actions

  void setMode(ScanMode m) {
    if (m == mode) return;
    mode = m;
    smoother.reset();
    detections = const [];
    sceneGuess = null;
    _lastScene = '';
    announcer.buzz(Buzz.light);
    _setStatus(m == ScanMode.currency ? 'Money mode. Point at a banknote.' : 'Objects mode. Describing surroundings.',
        speak: true);
  }

  Future<void> setTorch(bool on, {bool announce = true}) async {
    final c = camera;
    if (c == null) return;
    torchOn = on;
    if (!on) _torchAuto = false;
    await c.setFlashMode(on ? FlashMode.torch : FlashMode.off);
    if (announce) _setStatus(on ? 'Light on' : 'Light off', speak: true);
    notifyListeners();
  }

  Future<void> toggleTorch() => setTorch(!torchOn);

  void addToTotal() {
    final note = lastNote;
    if (note == null) {
      announcer.say('No note identified yet');
      return;
    }
    activity.addToTotal(note.currency, note.value);
    final total = activity.totals[note.currency]!;
    announcer.buzz(Buzz.success);
    _setStatus(
        settings.announceTotals
            ? 'Added ${note.spoken}. Total ${formatAmount(note.currency, total).split(' ').last} ${currencyName(note.currency)}.'
            : 'Added ${note.spoken}.',
        speak: true);
    lastNote = null; // the same sighting can't be added twice
    smoother.reset();
  }

  /// Guided multi-step counterfeit screening of the last identified note.
  Future<void> checkAuthenticity() async {
    final note = lastNote;
    final checker = authenticity;
    final c = camera;
    if (authRunning) return;
    if (note == null || checker == null || c == null) {
      await announcer.say('First point the camera at a note until it is identified.');
      return;
    }
    authNote = note;
    authResults.clear();
    verdict = null;
    authSteps = checker.stepsFor(note.currency, backlight: settings.backlightStep, uvLamp: settings.uvLampAvailable);
    if (authSteps.isEmpty) {
      verdict = Verdict.unavailable;
      authPhase = AuthPhase.done;
      final checks = checker.checksFor(note.currency).join(' ');
      _setStatus('Manual check for ${note.spoken}', speak: false);
      await announcer.say(
          'An automatic counterfeit check is not installed for ${currencyName(note.currency)}. Here is how to check by hand. $checks');
      return;
    }
    if (torchOn && _torchAuto) await setTorch(false, announce: false); // flash glare ruins texture
    try {
      await c.stopImageStream();
      for (authStepIndex = 0; authStepIndex < authSteps.length; authStepIndex++) {
        final step = authSteps[authStepIndex];
        authPhase = AuthPhase.instructing;
        _setStatus(AuthenticityChecker.stepName(step));
        await announcer.say(AuthenticityChecker.instruction(step));
        await Future<void>.delayed(const Duration(seconds: 4)); // time to position the note
        authPhase = AuthPhase.capturing;
        announcer.buzz(Buzz.light);
        notifyListeners();
        final shot = await c.takePicture();
        authPhase = AuthPhase.analysing;
        notifyListeners();
        authResults.add(await checker.runStep(note.currency, step, await shot.readAsBytes()));
        try {
          await File(shot.path).delete();
        } catch (_) {}
        if (authResults.last.failed) break; // no need to continue
      }
      verdict = AuthenticityChecker.combine(authResults);
      authPhase = AuthPhase.done;
      final (msg, sev, buzz) = switch (verdict!) {
        Verdict.noSignsOfCounterfeit => (
            'No counterfeit signs found for this ${note.spoken}. This is a screening, not a guarantee.',
            Severity.success,
            Buzz.success
          ),
        Verdict.possibleCounterfeit => (
            'Warning. This ${note.spoken} shows possible counterfeit signs. Please confirm with a bank or a trusted person. '
                '${checker.checksFor(note.currency).join(' ')}',
            Severity.danger,
            Buzz.danger
          ),
        Verdict.uncertain => (
            'Unclear result. Try again in good light with the note flat and filling the screen.',
            Severity.warning,
            Buzz.warning
          ),
        Verdict.unavailable => ('Counterfeit check unavailable.', Severity.info, Buzz.light),
      };
      announcer.buzz(buzz);
      _setStatus(msg.split('.').first, speak: false);
      await announcer.say(msg);
      activity.add(
          ActivityEvent(
              kind: ActivityKind.authenticity,
              severity: sev,
              title: '${formatAmount(note.currency, note.value)} · ${switch (verdict!) {
                Verdict.noSignsOfCounterfeit => 'No counterfeit signs',
                Verdict.possibleCounterfeit => 'Possible counterfeit',
                Verdict.uncertain => 'Inconclusive',
                Verdict.unavailable => 'Manual check',
              }}',
              detail: [
                for (final r in authResults)
                  '${AuthenticityChecker.stepName(r.step)}: ${r.failed ? 'failed' : r.clearlyPassed ? 'passed' : 'unclear'}'
              ].join(' · ')),
          popUp: verdict == Verdict.possibleCounterfeit);
    } on CameraException catch (e) {
      authPhase = AuthPhase.done;
      verdict = Verdict.uncertain;
      _setStatus('Could not take picture: ${e.code}', speak: true);
    } finally {
      if (camera != null && !camera!.value.isStreamingImages) await camera!.startImageStream(_onFrame);
      notifyListeners();
    }
  }

  void dismissAuthResult() {
    authPhase = AuthPhase.idle;
    notifyListeners();
  }

  // ---------------------------------------------------------------- helpers

  void _hint(String text, {bool speak = true}) {
    hint = text;
    final now = DateTime.now();
    if (now.difference(_lastHint) < const Duration(seconds: 5)) {
      notifyListeners();
      return;
    }
    _lastHint = now;
    notifyListeners();
    if (speak) announcer.say(text);
  }

  void _setStatus(String text, {bool speak = false}) {
    status = text;
    notifyListeners();
    if (speak) announcer.say(text);
  }

  @override
  void dispose() {
    stopCamera();
    _classifier?.close();
    _detector?.close();
    _scene?.close();
    authenticity?.close();
    announcer.dispose();
    super.dispose();
  }
}
