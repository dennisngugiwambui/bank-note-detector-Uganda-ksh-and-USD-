import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'core/activity.dart';
import 'core/currency.dart';
import 'core/note_facts.dart';
import 'core/settings.dart';
import 'core/strings.dart';
import 'ml/authenticity_checker.dart';
import 'ml/currency_classifier.dart';
import 'ml/frame.dart';
import 'ml/frame_worker.dart';
import 'ml/object_detector.dart';
import 'ml/scene_classifier.dart';
import 'ml/scene_speech.dart';
import 'ml/scene_tracker.dart';
import 'services/announcer.dart';
import 'services/pose_sensor.dart';

enum ScanMode { currency, scene }

enum ModelPart { money, objects, scene, tools }

/// How far the models are from ready.
class LoadProgress {
  final double progress; // 0..1
  final int secondsLeft;
  final Set<ModelPart> finished;
  final bool done;
  const LoadProgress({this.progress = 0, this.secondsLeft = 4, this.finished = const {}, this.done = false});
  int get percent => (progress * 100).round().clamp(0, 100);
}

enum AuthPhase { idle, instructing, capturing, analysing, done }

/// All scanning logic, with no widgets: camera, models, tracking, spoken
/// output, safety alerts, teaching notes and the guided authenticity check.
/// Screens listen through ChangeNotifier.
///
/// Objects mode runs frames back to back (no fixed interval): the detector on
/// every frame, the money classifier on every 2nd and the scene classifier on
/// every 3rd. Warnings come from the tracker's distance and time-to-contact,
/// so they are spoken while the object is still a few steps away.
class ScanController extends ChangeNotifier {
  static const darkLuma = 40.0;
  static const minSharpness = 25.0;
  static const currencyInterval = Duration(milliseconds: 120);

  final AppSettings settings;
  final ActivityStore activity;
  final Announcer announcer;
  final PredictionSmoother smoother = PredictionSmoother();
  late PredictionSmoother _bgSmoother = PredictionSmoother.background(settings.sensitivity);
  final SceneTracker tracker = SceneTracker();
  final PoseSensor pose = PoseSensor();

  ScanController({required this.settings, required this.activity}) : announcer = Announcer(settings);

  S get s => settings.strings;
  SceneSpeech get _speech =>
      SceneSpeech(s, direction: settings.directionStyle, unit: settings.distanceUnit);

  CameraController? camera;
  CurrencyClassifier? _classifier;
  ObjectDetector? _detector;
  SceneClassifier? _scene;
  AuthenticityChecker? authenticity;
  FrameWorker? _worker;
  bool modelsLoaded = false;

  ScanMode mode = ScanMode.currency;
  String status = '';
  String? hint;
  Note? lastNote;
  Note? lastSeen; // kept after "add" clears lastNote, for "details"
  double lastConfidence = 0;
  List<Tracked> tracked = const [];
  String? sceneGuess; // ImageNet fallback, e.g. "shoes"
  double sceneGuessScore = 0;
  bool torchOn = false;
  bool lookingDown = false;

  /// "Teach a note": the note being taught and how many samples so far.
  Note? teaching;
  int teachSamples = 0;
  static const teachTarget = 24;

  // Authenticity flow state, shown by the UI
  AuthPhase authPhase = AuthPhase.idle;
  List<AuthStep> authSteps = const [];
  int authStepIndex = 0;
  final List<StepResult> authResults = [];
  Verdict? verdict;
  Note? authNote;

  bool _busy = false;
  bool _torchAuto = false;
  int _frameNo = 0;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastHint = DateTime.fromMillisecondsSinceEpoch(0);
  final _clock = Stopwatch()..start();

  // Objects-mode speech state
  String _lastSig = '';
  String _pendingSig = '';
  int _sigStable = 0;
  DateTime _lastDescribedAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<int, (Hazard, DateTime)> _alerted = {};
  DateTime _lastPulse = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastTeachSample = DateTime.fromMillisecondsSinceEpoch(0);

  bool get hasCurrencyModel => _classifier != null;
  bool get canTeach => _classifier?.canLearn ?? false;
  TaughtNotes? get taughtNotes => _classifier?.taught;
  bool get hasDetector => _detector != null;
  bool get hasSceneClassifier => _scene != null;
  bool get authRunning => authPhase != AuthPhase.idle && authPhase != AuthPhase.done;

  /// Start-up progress of the on-device models, shown by [ModelLoadingCard]
  /// and announced when it takes more than a moment.
  final ValueNotifier<LoadProgress> loading = ValueNotifier(const LoadProgress());
  Future<void>? _loadingModels;

  Future<void> loadModels() => _loadingModels ??= _loadModels();

  Future<void> _loadModels() async {
    await announcer.init();
    final clock = Stopwatch()..start();
    var done = 0.0;
    final finished = <ModelPart>{};
    // Weights follow the model sizes, so the bar moves at an even pace.
    const weights = {ModelPart.money: 0.35, ModelPart.objects: 0.4, ModelPart.scene: 0.2, ModelPart.tools: 0.05};
    void publish({bool complete = false}) {
      final secs = clock.elapsedMilliseconds / 1000;
      // Until something finishes, assume a typical 4 s start; then use the real rate.
      final eta = complete ? 0.0 : (done < 0.05 ? (4 - secs).clamp(1, 4) : secs * (1 - done) / done);
      loading.value = LoadProgress(
          progress: complete ? 1 : done, secondsLeft: eta.ceil(), finished: {...finished}, done: complete);
    }

    Future<T> track<T>(ModelPart part, Future<T> f) => f.then((v) {
          done += weights[part]!;
          finished.add(part);
          publish();
          return v;
        });

    publish();
    // Speak only if the start is slow, so a quick start stays quiet.
    final slow = Timer(const Duration(milliseconds: 1500), () {
      if (!loading.value.done) {
        announcer.say(s.gettingReady(loading.value.secondsLeft), priority: Priority.normal);
      }
    });
    // Smooth the bar between finished models, never past the next one.
    final creep = Timer.periodic(const Duration(milliseconds: 120), (_) {
      final v = loading.value;
      if (v.done) return;
      final cap = (done + 0.9 * (1 - done) * 0.5).clamp(0.0, 0.97);
      if (v.progress < cap) {
        loading.value = LoadProgress(
            progress: v.progress + (cap - v.progress) * 0.08,
            secondsLeft: v.secondsLeft,
            finished: v.finished);
      }
    });
    final loaded = await Future.wait<Object?>([
      track(ModelPart.money, CurrencyClassifier.load()),
      track(ModelPart.objects, ObjectDetector.load()),
      track(ModelPart.tools, Future.wait([AuthenticityChecker.load(), FrameWorker.start()])),
      track(ModelPart.scene, SceneClassifier.load()),
    ]);
    slow.cancel();
    creep.cancel();
    _classifier = loaded[0] as CurrencyClassifier?;
    _detector = loaded[1] as ObjectDetector?;
    final tools = loaded[2] as List<Object>;
    authenticity = tools[0] as AuthenticityChecker;
    _worker = tools[1] as FrameWorker;
    _scene = loaded[3] as SceneClassifier?;
    modelsLoaded = true;
    publish(complete: true);
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
      pose.start();
      await c.startImageStream(_onFrame);
      await WakelockPlus.enable();
      if (!hasCurrencyModel && mode == ScanMode.currency) {
        _setStatus(s.modelMissing, speak: true);
      } else {
        _setStatus(mode == ScanMode.currency ? s.moneyMode : s.objectsMode, speak: true);
      }
    } on CameraException catch (e) {
      _setStatus(s.cameraUnavailable(e.description ?? e.code), speak: true);
    }
  }

  Future<void> stopCamera() async {
    final c = camera;
    camera = null;
    torchOn = false;
    _torchAuto = false;
    pose.stop();
    tracker.reset();
    tracked = const [];
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
    if (_busy || authRunning) return;
    if (mode == ScanMode.currency && now.difference(_lastFrame) < currencyInterval) return;
    _busy = true;
    _lastFrame = now;
    _frameNo++;
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

  // ---------------------------------------------------------------- money

  Future<void> _handleCurrency(FrameData frame) async {
    final classifier = _classifier, worker = _worker;
    if (classifier == null || worker == null) return;
    final input = (await worker.prepare(frame, [(classifier.inputSize, true)])).first;
    if (input.brightness < darkLuma) {
      if (settings.autoTorch && !torchOn) {
        _torchAuto = true;
        await setTorch(true, announce: false);
        _hint(s.lowLightTorch);
      } else {
        _hint(s.tooDark);
      }
      return;
    }
    if (input.sharpness < minSharpness) {
      _hint(s.holdSteady, speak: false);
      return;
    }
    hint = null;
    var p = await classifier.classify(input.rgb);
    if (teaching != null) {
      await _teachStep(p);
      return;
    }
    p = _filterCurrency(p);
    smoother.threshold = settings.sensitivity;
    lastConfidence = p.confidence;
    final note = smoother.add(p);
    if (note != null) {
      _announceNote(note, p.confidence);
    } else if (p.label == backgroundLabel && p.confidence > 0.8 && status != s.noNote) {
      _setStatus(s.noNote);
    } else {
      notifyListeners(); // live confidence gauge
    }
  }

  /// Currencies switched off in settings count as "no money".
  Prediction _filterCurrency(Prediction p) {
    final parsed = Note.parse(p.label);
    if (parsed != null && !settings.enabledCurrencies.contains(parsed.currency)) {
      return Prediction(backgroundLabel, p.confidence);
    }
    return p;
  }

  void _announceNote(Note note, double confidence, {bool inObjectsMode = false}) {
    lastNote = note;
    lastSeen = note;
    final spoken = note.spokenIn(s);
    announcer.buzz(Buzz.success);
    final brief = settings.noteFeatures ? briefFor(note, s) : null;
    final named = inObjectsMode ? s.banknoteFound(spoken) : spoken;
    final text = brief == null ? named : '$named. $brief.';
    status = text;
    notifyListeners();
    announcer.say(text, priority: inObjectsMode ? Priority.high : Priority.normal, dedupe: Duration.zero);
    activity.add(ActivityEvent(
        kind: ActivityKind.note,
        severity: Severity.success,
        title: formatAmount(note.currency, note.value),
        detail: '${note.spoken} · ${(confidence * 100).round()}%'));
  }

  // ---------------------------------------------------------------- teach

  /// Starts teaching [note]: the camera collects embeddings of the note held
  /// in front of it, front, back and at angles.
  void startTeach(Note note) {
    if (!canTeach) return;
    teaching = note;
    teachSamples = 0;
    setMode(ScanMode.currency, announce: false);
    _setStatus(s.teachFront(note.spokenIn(s)), speak: true);
  }

  void cancelTeach() {
    teaching = null;
    notifyListeners();
  }

  Future<void> _teachStep(Prediction p) async {
    final note = teaching!, f = p.features;
    final now = DateTime.now();
    if (f == null || now.difference(_lastTeachSample) < const Duration(milliseconds: 250)) return;
    _lastTeachSample = now;
    await _classifier!.taught.add(note.label, f);
    teachSamples++;
    announcer.buzz(Buzz.light);
    if (teachSamples == teachTarget ~/ 3) _setStatus(s.teachBack, speak: true);
    if (teachSamples == 2 * teachTarget ~/ 3) _setStatus(s.teachTilt, speak: true);
    if (teachSamples >= teachTarget) {
      teaching = null;
      smoother.reset();
      announcer.buzz(Buzz.success);
      _setStatus(s.teachDone(note.spokenIn(s)), speak: true);
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- surroundings

  Future<void> _handleScene(FrameData frame) async {
    final detector = _detector, worker = _worker;
    if (detector == null || worker == null) {
      _hint(s.t('Object recognition is not installed', 'Utambuzi wa vitu haujasakinishwa'));
      return;
    }
    final scene = _scene, classifier = _classifier;
    final wantScene = scene != null && _frameNo % 3 == 0;
    final wantMoney = classifier != null && settings.notesInObjectsMode && _frameNo % 2 == 0;
    final inputs = await worker.prepare(frame, [
      (detector.inputWidth, false),
      if (wantScene) (scene.inputSize, false),
      if (wantMoney) (classifier.inputSize, true),
    ]);
    final t = _clock.elapsedMilliseconds / 1000;
    final dets = await detector.detect(inputs[0].rgb, minScore: 0.3);
    final p = pose.current;
    lookingDown = p.lookingDown;
    tracker.warnDistance = settings.warnDistance;
    tracked = tracker.update(dets, t, p, frame.uprightW / frame.uprightH);

    if (wantScene) {
      final guess = await scene.classify(inputs[1].rgb, minScore: 0.35);
      sceneGuess = guess?.$1;
      sceneGuessScore = guess?.$2 ?? 0;
    }
    if (wantMoney) {
      final m = _filterCurrency(await classifier.classify(inputs.last.rgb));
      _bgSmoother.threshold = settings.sensitivity < 0.92 ? 0.92 : settings.sensitivity;
      final note = _bgSmoother.add(m);
      if (note != null) _announceNote(note, m.confidence, inObjectsMode: true);
    }

    final alerted = settings.obstacleAlerts && _checkHazards(tracked);
    if (settings.proximityVibration) _proximityPulse(tracked);
    if (!alerted) _describe(tracked);
    notifyListeners();
  }

  /// Speaks the most dangerous object. Returns true if something was said.
  bool _checkHazards(List<Tracked> objects) {
    if (lookingDown) return false;
    Tracked? worst;
    for (final o in objects) {
      if (o.hazard == Hazard.none) continue;
      if (worst == null ||
          o.hazard.index > worst.hazard.index ||
          (o.hazard == worst.hazard && (o.distance ?? 99) < (worst.distance ?? 99))) {
        worst = o;
      }
    }
    if (worst == null) return false;
    final now = DateTime.now();
    final prev = _alerted[worst.id];
    // Repeat for the same object only when it got more dangerous, or after a pause.
    final escalated = prev == null || worst.hazard.index > prev.$1.index;
    final pause = worst.hazard == Hazard.danger ? const Duration(seconds: 3) : const Duration(seconds: 6);
    if (!escalated && now.difference(prev.$2) < pause) return false;
    _alerted[worst.id] = (worst.hazard, now);
    _alerted.removeWhere((id, v) => now.difference(v.$2) > const Duration(seconds: 30));

    final danger = worst.hazard == Hazard.danger;
    final text = _speech.alert(worst);
    announcer.buzz(danger ? Buzz.danger : Buzz.warning);
    announcer.say(text, priority: danger ? Priority.urgent : Priority.high, dedupe: Duration.zero);
    status = text;
    _lastSig = _speech.signature(objects); // don't describe the same scene right after
    _lastDescribedAt = now;
    activity.add(
        ActivityEvent(
            kind: ActivityKind.obstacle,
            severity: danger ? Severity.danger : Severity.warning,
            title: _speech.one(worst, withApproach: false),
            detail: worst.approaching ? s.approaching : s.inYourPath),
        popUp: settings.showAlertBanners);
    return true;
  }

  /// Short vibrations, faster as the nearest thing in the path gets closer,
  /// like a parking sensor.
  void _proximityPulse(List<Tracked> objects) {
    if (lookingDown) return;
    double? nearest;
    for (final o in objects) {
      if (!o.inPath || o.distance == null) continue;
      if (nearest == null || o.distance! < nearest) nearest = o.distance;
    }
    if (nearest == null || nearest > settings.warnDistance) return;
    final gap = Duration(milliseconds: (nearest * 450).clamp(220, 1600).round());
    final now = DateTime.now();
    if (now.difference(_lastPulse) < gap) return;
    _lastPulse = now;
    announcer.buzz(Buzz.pulse);
  }

  /// Calm description, only when what would be said changed and stayed
  /// changed for two frames, or as a reminder every 8 seconds.
  void _describe(List<Tracked> objects) {
    final now = DateTime.now();
    if (lookingDown && objects.isEmpty) {
      _hint(s.pointingDown, speak: true);
      return;
    }
    final sig = '${_speech.signature(objects)}|$sceneGuess';
    if (sig == _pendingSig) {
      _sigStable++;
    } else {
      _pendingSig = sig;
      _sigStable = 1;
    }
    final changed = sig != _lastSig && _sigStable >= 2;
    final reminder = objects.isNotEmpty && now.difference(_lastDescribedAt) > const Duration(seconds: 8);
    if (!changed && !reminder) return;
    final text = _speech.describe(objects, sceneGuess: sceneGuess);
    if (objects.isEmpty && sceneGuess == null && _lastSig.isEmpty) return; // nothing new to say
    _lastSig = sig;
    _lastDescribedAt = now;
    status = text;
    announcer.say(text, priority: changed ? Priority.normal : Priority.low);
  }

  // ---------------------------------------------------------------- actions

  void setMode(ScanMode m, {bool announce = true}) {
    if (m == mode) return;
    mode = m;
    smoother.reset();
    _bgSmoother = PredictionSmoother.background(settings.sensitivity);
    tracker.reset();
    tracked = const [];
    sceneGuess = null;
    _lastSig = '';
    _pendingSig = '';
    if (m == ScanMode.scene) teaching = null;
    announcer.buzz(Buzz.light);
    if (announce) {
      _setStatus(m == ScanMode.currency ? s.moneyMode : s.objectsMode, speak: true);
    } else {
      notifyListeners();
    }
  }

  Future<void> setTorch(bool on, {bool announce = true}) async {
    final c = camera;
    if (c == null) return;
    torchOn = on;
    if (!on) _torchAuto = false;
    try {
      await c.setFlashMode(on ? FlashMode.torch : FlashMode.off);
    } catch (_) {}
    if (announce) _setStatus(on ? s.lightOn : s.lightOff, speak: true);
    notifyListeners();
  }

  Future<void> toggleTorch() => setTorch(!torchOn);

  /// Says how to use the current mode.
  void repeatModeHint() =>
      announcer.say(mode == ScanMode.currency ? s.moneyMode : s.objectsMode, priority: Priority.high, dedupe: Duration.zero);

  /// Says the last result again, at once.
  void repeatLast() {
    final text = status.isEmpty ? (mode == ScanMode.currency ? s.pointAtNote : s.describing) : status;
    announcer.say(text, priority: Priority.urgent, dedupe: Duration.zero);
  }

  /// Reads everything known about the last note: colour, animal, pictures
  /// and what to feel for.
  void describeNote() {
    final note = lastSeen;
    if (note == null) {
      announcer.say(s.noNoteYet, priority: Priority.high);
      return;
    }
    announcer.say(detailsFor(note, s), priority: Priority.urgent, dedupe: Duration.zero);
  }

  /// Describes the surroundings right now, whatever changed.
  void describeNow() {
    if (mode != ScanMode.scene) return repeatLast();
    final text = _speech.describe(tracked, sceneGuess: sceneGuess);
    status = text;
    announcer.say(text, priority: Priority.urgent, dedupe: Duration.zero);
    notifyListeners();
  }

  void addToTotal() {
    final note = lastNote;
    if (note == null) {
      announcer.say(s.noNoteYet, priority: Priority.high);
      return;
    }
    activity.addToTotal(note.currency, note.value);
    final total = activity.totals[note.currency]!;
    announcer.buzz(Buzz.success);
    final spoken = note.spokenIn(s);
    _setStatus(
        settings.announceTotals ? s.addedTotal(spoken, s.noteName(note.currency, total)) : s.added(spoken),
        speak: true);
    lastNote = null; // the same sighting can't be added twice
    smoother.reset();
  }

  /// "Your total is 1,500 Kenyan shillings and 20 US dollars."
  String totalsSentence() {
    final t = activity.totals.entries.where((e) => e.value > 0).toList();
    if (t.isEmpty) return s.noTotals;
    return s.totals(t.map((e) => s.noteName(e.key, e.value)).join(s.t(' and ', ' na ')));
  }

  /// Guided multi-step counterfeit screening of the last identified note.
  Future<void> checkAuthenticity() async {
    final note = lastNote;
    final checker = authenticity;
    final c = camera;
    if (authRunning) return;
    if (note == null || checker == null || c == null) {
      await announcer.say(s.firstIdentify, priority: Priority.high);
      return;
    }
    final spoken = note.spokenIn(s);
    authNote = note;
    authResults.clear();
    verdict = null;
    authSteps = checker.stepsFor(note.currency, backlight: settings.backlightStep, uvLamp: settings.uvLampAvailable);
    if (authSteps.isEmpty) {
      verdict = Verdict.unavailable;
      authPhase = AuthPhase.done;
      final checks = checker.checksFor(note.currency).join(' ');
      _setStatus(s.t('Manual check for $spoken', 'Ukaguzi wa mkono kwa $spoken'));
      await announcer.say(
          s.t('An automatic counterfeit check is not installed for ${s.currencyName(note.currency)}. Here is how to check by hand. $checks',
              'Ukaguzi wa bandia wa kiotomatiki haujasakinishwa kwa ${s.currencyName(note.currency)}. $checks'),
          priority: Priority.high);
      return;
    }
    if (torchOn && _torchAuto) await setTorch(false, announce: false); // flash glare ruins texture
    try {
      await c.stopImageStream();
      for (authStepIndex = 0; authStepIndex < authSteps.length; authStepIndex++) {
        final step = authSteps[authStepIndex];
        authPhase = AuthPhase.instructing;
        _setStatus(AuthenticityChecker.stepName(step));
        await announcer.say(AuthenticityChecker.instruction(step), priority: Priority.high);
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
            s.t('No counterfeit signs found for this $spoken. This is a screening, not a guarantee.',
                'Hakuna dalili za bandia kwenye $spoken hii. Huu ni uchunguzi tu, si uhakika.'),
            Severity.success,
            Buzz.success
          ),
        Verdict.possibleCounterfeit => (
            s.t('Warning. This $spoken shows possible counterfeit signs. Please confirm with a bank or a trusted person. ',
                    'Tahadhari. $spoken hii ina dalili za bandia. Tafadhali thibitisha benki au kwa mtu unayemwamini. ') +
                checker.checksFor(note.currency).join(' '),
            Severity.danger,
            Buzz.danger
          ),
        Verdict.uncertain => (
            s.t('Unclear result. Try again in good light with the note flat and filling the screen.',
                'Jibu halieleweki. Jaribu tena kwenye mwanga mzuri, noti ikiwa bapa na ikijaza skrini.'),
            Severity.warning,
            Buzz.warning
          ),
        Verdict.unavailable => (s.t('Counterfeit check unavailable.', 'Ukaguzi wa bandia haupatikani.'), Severity.info, Buzz.light),
      };
      announcer.buzz(buzz);
      _setStatus(msg.split('.').first);
      await announcer.say(msg, priority: Priority.high);
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
          popUp: settings.showAlertBanners && verdict == Verdict.possibleCounterfeit);
    } on CameraException catch (e) {
      authPhase = AuthPhase.done;
      verdict = Verdict.uncertain;
      _setStatus(s.t('Could not take picture: ${e.code}', 'Imeshindwa kupiga picha: ${e.code}'), speak: true);
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
    if (now.difference(_lastHint) < const Duration(seconds: 6)) {
      notifyListeners();
      return;
    }
    _lastHint = now;
    notifyListeners();
    if (speak) announcer.say(text, priority: Priority.low);
  }

  void _setStatus(String text, {bool speak = false}) {
    status = text;
    notifyListeners();
    if (speak) announcer.say(text, priority: Priority.high, dedupe: Duration.zero);
  }

  @override
  void dispose() {
    stopCamera();
    _worker?.close();
    _classifier?.close();
    _detector?.close();
    _scene?.close();
    authenticity?.close();
    announcer.dispose();
    super.dispose();
  }
}
