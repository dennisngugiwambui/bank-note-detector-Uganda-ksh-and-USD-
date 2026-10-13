import 'package:flutter/services.dart';

import 'tflite_model.dart';

class Detection {
  final String label;
  final double score;
  final double left, top, right, bottom; // normalized 0..1, upright frame
  const Detection(this.label, this.score, this.left, this.top, this.right, this.bottom);

  double get centerX => (left + right) / 2;
  double get area => (right - left) * (bottom - top);
}

/// General object detection ("what is in front of me"), for COCO models
/// with the TFLite_Detection_PostProcess op: the SSD MobileNet `detect.tflite`
/// from Blind-People-Smart-AID / Braillo, or EfficientDet-Lite0 (recommended,
/// more accurate).
///
/// Those models order their four outputs differently, so the roles are
/// worked out from shapes and values rather than hard-coded.
class ObjectDetector {
  static const modelAsset = 'assets/detector/model.tflite';
  static const labelsAsset = 'assets/detector/labels.txt';

  final TfliteModel _model;
  final List<String> _labels;
  final int _labelOffset;
  ObjectDetector._(this._model, this._labels, this._labelOffset);

  int get inputWidth => _model.inputWidth;
  int get inputHeight => _model.inputHeight;

  static Future<ObjectDetector?> load() async {
    final model = await TfliteModel.load(modelAsset, normalizeFloatInput: true);
    if (model == null) return null;
    final labels = (await rootBundle.loadString(labelsAsset))
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    // TF Object Detection API label maps begin with a "???" placeholder.
    return ObjectDetector._(model, labels, labels.isNotEmpty && labels.first == '???' ? 1 : 0);
  }

  Future<List<Detection>> detect(Uint8List rgb, {double minScore = 0.5}) async {
    final outs = await _model.run(rgb);
    final shapes = _model.outputShapes;

    List<double>? boxes, count;
    final perDetection = <List<double>>[];
    for (var i = 0; i < outs.length; i++) {
      if (shapes[i].length == 3 && shapes[i].last == 4) {
        boxes = outs[i];
      } else if (outs[i].length == 1) {
        count = outs[i];
      } else {
        perDetection.add(outs[i]);
      }
    }
    if (boxes == null || perDetection.length != 2) return const [];
    // Scores lie in [0, 1]. Class ids are whole numbers, and some are > 1.
    bool looksLikeClasses(List<double> v) => v.any((x) => x > 1.0) || v.every((x) => x == x.roundToDouble());
    final classes = looksLikeClasses(perDetection[0]) ? perDetection[0] : perDetection[1];
    final scores = identical(classes, perDetection[0]) ? perDetection[1] : perDetection[0];

    final n = count != null ? count.first.toInt().clamp(0, scores.length).toInt() : scores.length;
    final result = <Detection>[];
    for (var i = 0; i < n; i++) {
      if (scores[i] < minScore) continue;
      final idx = classes[i].toInt() + _labelOffset;
      if (idx < 0 || idx >= _labels.length) continue;
      final label = _labels[idx];
      if (label == '???' || label.isEmpty) continue;
      result.add(Detection(label, scores[i], boxes[i * 4 + 1].clamp(0.0, 1.0).toDouble(),
          boxes[i * 4].clamp(0.0, 1.0).toDouble(), boxes[i * 4 + 3].clamp(0.0, 1.0).toDouble(),
          boxes[i * 4 + 2].clamp(0.0, 1.0).toDouble()));
    }
    result.sort((a, b) => b.score.compareTo(a.score));
    return result;
  }

  void close() => _model.close();
}

/// Builds a short spoken scene description, such as "person ahead, close.
/// Chair on your left."
String describeScene(List<Detection> detections, {int maxItems = 3}) {
  if (detections.isEmpty) return 'Nothing recognized';
  final seen = <String>{};
  final parts = <String>[];
  for (final d in detections) {
    if (!seen.add(d.label)) continue;
    final where = d.centerX < 0.33 ? 'on your left' : d.centerX > 0.66 ? 'on your right' : 'ahead';
    parts.add('${d.label} $where${d.area > 0.35 ? ', close' : ''}');
    if (parts.length == maxItems) break;
  }
  return parts.join('. ');
}
