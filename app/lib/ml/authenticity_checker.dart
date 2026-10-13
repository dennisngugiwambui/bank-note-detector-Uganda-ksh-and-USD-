import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'tflite_model.dart';

/// Guided counterfeit screening, adapted from the three-light method of
/// bkataru/fake-currency-identification (front, back and UV light). Here a
/// phone replaces the Raspberry Pi rig:
///  * print:     a still in normal light; a patch model looks for printer/copier texture
///  * backlight: the user holds the note against a window or lamp, and the watermark must show
///  * uv:        optional, with a 365 nm UV lamp; the fluorescent thread or fibres must glow
///
/// Each step is enabled per currency by dropping a model into
/// `assets/authenticity/<ISO>/` (print: model.tflite, backlight.tflite,
/// uv.tflite). Every model is binary, with labels [genuine, counterfeit].
/// Currencies without models fall back to spoken manual checks.
enum AuthStep { print, backlight, uv }

enum Verdict { noSignsOfCounterfeit, uncertain, possibleCounterfeit, unavailable }

class StepResult {
  final AuthStep step;
  final double counterfeitScore;
  final double threshold;
  const StepResult(this.step, this.counterfeitScore, this.threshold);

  bool get failed => counterfeitScore >= threshold;
  bool get clearlyPassed => counterfeitScore <= threshold * 0.4;
}

class _StepModel {
  final TfliteModel model;
  final double threshold;
  _StepModel(this.model, this.threshold);
}

class AuthenticityChecker {
  // Keep in sync with training/train_authenticity.py
  static const shortSide = 448;
  static const patch = 224;
  static const grid = 3;

  static const _files = {AuthStep.print: 'model', AuthStep.backlight: 'backlight', AuthStep.uv: 'uv'};

  final Map<String, Map<AuthStep, _StepModel>> _models;
  final Map<String, List<String>> manualChecks;
  AuthenticityChecker._(this._models, this.manualChecks);

  static String instruction(AuthStep step) => switch (step) {
        AuthStep.print => 'Lay the note flat in good light so it fills the screen. Hold still.',
        AuthStep.backlight =>
          'Now hold the note up against a bright window or lamp, so light shines through it. Hold still.',
        AuthStep.uv => 'Switch on your UV lamp and shine it on the note, in a dim place. Hold still.',
      };

  static String stepName(AuthStep step) => switch (step) {
        AuthStep.print => 'Print quality',
        AuthStep.backlight => 'Watermark (backlight)',
        AuthStep.uv => 'UV features',
      };

  static Future<AuthenticityChecker> load() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final pattern = RegExp(r'^assets/authenticity/([A-Z]{3})/(model|backlight|uv)\.tflite$');
    final models = <String, Map<AuthStep, _StepModel>>{};
    for (final asset in manifest.listAssets()) {
      final m = pattern.firstMatch(asset);
      if (m == null) continue;
      final iso = m.group(1)!;
      final step = _files.entries.firstWhere((e) => e.value == m.group(2)).key;
      final model = await TfliteModel.load(asset);
      if (model == null) continue;
      final prefix = step == AuthStep.print ? '' : '${m.group(2)}_';
      var threshold = 0.5;
      try {
        threshold = double.parse((await rootBundle.loadString('assets/authenticity/$iso/${prefix}threshold.txt')).trim());
      } catch (_) {}
      (models[iso] ??= {})[step] = _StepModel(model, threshold);
    }
    final checksJson = jsonDecode(await rootBundle.loadString('assets/security_features.json')) as Map<String, dynamic>;
    final checks = {
      for (final e in checksJson.entries)
        if (e.value is List) e.key: (e.value as List).cast<String>(),
    };
    return AuthenticityChecker._(models, checks);
  }

  bool supports(String iso) => _models[iso]?.isNotEmpty ?? false;

  /// The steps this device can run for [iso], in order.
  List<AuthStep> stepsFor(String iso, {required bool backlight, required bool uvLamp}) {
    final available = _models[iso] ?? const {};
    return [
      if (available.containsKey(AuthStep.print)) AuthStep.print,
      if (backlight && available.containsKey(AuthStep.backlight)) AuthStep.backlight,
      if (uvLamp && available.containsKey(AuthStep.uv)) AuthStep.uv,
    ];
  }

  List<String> checksFor(String iso) => manualChecks[iso] ?? manualChecks['DEFAULT'] ?? const [];

  /// [jpeg]: a full-resolution still from CameraController.takePicture().
  Future<StepResult> runStep(String iso, AuthStep step, Uint8List jpeg) async {
    final m = _models[iso]![step]!;
    // Print: fine texture, so high-resolution patches. Backlight and UV:
    // large features, so the whole letterboxed frame.
    final inputs = step == AuthStep.print
        ? await Isolate.run(() => _gridPatches(jpeg))
        : await Isolate.run(() => _whole(jpeg, m.model.inputHeight));
    if (inputs.isEmpty) return StepResult(step, m.threshold * 0.7, m.threshold); // unreadable: uncertain
    var sum = 0.0;
    for (final x in inputs) {
      sum += (await m.model.run(x)).first[1]; // index 1 = counterfeit
    }
    return StepResult(step, sum / inputs.length, m.threshold);
  }

  /// Any failed step means "possible counterfeit". All steps clearly passing
  /// means "no signs". Anything else is uncertain.
  static Verdict combine(List<StepResult> results) {
    if (results.isEmpty) return Verdict.unavailable;
    if (results.any((r) => r.failed)) return Verdict.possibleCounterfeit;
    if (results.every((r) => r.clearlyPassed)) return Verdict.noSignsOfCounterfeit;
    return Verdict.uncertain;
  }

  static List<Uint8List> _gridPatches(Uint8List jpeg) {
    final decoded = img.decodeImage(jpeg);
    if (decoded == null) return const [];
    var im = img.bakeOrientation(decoded);
    final f = shortSide / (im.width < im.height ? im.width : im.height);
    im = img.copyResize(im,
        width: (im.width * f).round().clamp(patch, 1 << 14).toInt(),
        height: (im.height * f).round().clamp(patch, 1 << 14).toInt(),
        interpolation: img.Interpolation.linear);
    final out = <Uint8List>[];
    for (var gy = 0; gy < grid; gy++) {
      for (var gx = 0; gx < grid; gx++) {
        final x = ((im.width - patch) * gx / (grid - 1)).round();
        final y = ((im.height - patch) * gy / (grid - 1)).round();
        out.add(img.copyCrop(im, x: x, y: y, width: patch, height: patch).getBytes(order: img.ChannelOrder.rgb));
      }
    }
    return out;
  }

  /// Letterboxed to size x size on black, the same as training/data.py.
  static List<Uint8List> _whole(Uint8List jpeg, int size) {
    final decoded = img.decodeImage(jpeg);
    if (decoded == null) return const [];
    final im = img.bakeOrientation(decoded);
    final f = size / (im.width > im.height ? im.width : im.height);
    final w = (im.width * f).round(), h = (im.height * f).round();
    final resized = img.copyResize(im, width: w, height: h, interpolation: img.Interpolation.linear);
    final canvas = img.Image(width: size, height: size);
    img.compositeImage(canvas, resized, dstX: (size - w) ~/ 2, dstY: (size - h) ~/ 2);
    return [canvas.getBytes(order: img.ChannelOrder.rgb)];
  }

  void close() {
    for (final steps in _models.values) {
      for (final m in steps.values) {
        m.model.close();
      }
    }
  }
}
