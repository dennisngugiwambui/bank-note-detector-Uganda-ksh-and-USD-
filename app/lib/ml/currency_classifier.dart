import 'package:flutter/services.dart';

import '../core/currency.dart';
import 'tflite_model.dart';

class Prediction {
  final String label;
  final double confidence;
  const Prediction(this.label, this.confidence);
}

/// The multi-currency denomination classifier. Its output is softmax(logits/T),
/// already calibrated during training.
class CurrencyClassifier {
  static const modelAsset = 'assets/currency/model.tflite';
  static const labelsAsset = 'assets/currency/labels.txt';

  final TfliteModel _model;
  final List<String> labels;
  CurrencyClassifier._(this._model, this.labels);

  int get inputSize => _model.inputHeight;

  static Future<CurrencyClassifier?> load() async {
    final model = await TfliteModel.load(modelAsset);
    if (model == null) return null;
    final labels = (await rootBundle.loadString(labelsAsset))
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return CurrencyClassifier._(model, labels);
  }

  Future<Prediction> classify(Uint8List rgb) async {
    final probs = (await _model.run(rgb)).first;
    var best = 0;
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > probs[best]) best = i;
    }
    return Prediction(labels[best], probs[best]);
  }

  void close() => _model.close();
}

/// Turns per-frame predictions into one stable announcement.
///
/// The reference apps speak from a single frame: Braillo at more than 0.4,
/// Noteify at more than 0.5. Single frames flicker while a hand moves the
/// note. Here a note is announced only when it wins [minVotes] of the last
/// [window] frames, each at or above [threshold]. Then it is not repeated
/// until the camera has seen no note for a few frames, so a new note of the
/// same value is still announced.
class PredictionSmoother {
  /// Calibrate with training/evaluate_tflite.py (lowest threshold with >= 99% precision).
  double threshold;
  final int window, minVotes;
  final List<String?> _history = [];
  String? _lastAnnounced;
  int _emptyStreak = 0;

  PredictionSmoother({this.threshold = 0.85, this.window = 7, this.minVotes = 5});

  /// Returns a note when it should be announced now.
  Note? add(Prediction p) {
    final note = p.confidence >= threshold ? Note.parse(p.label) : null;
    _history.add(note?.label);
    if (_history.length > window) _history.removeAt(0);

    final isBackground = p.label == backgroundLabel && p.confidence >= threshold;
    _emptyStreak = isBackground ? _emptyStreak + 1 : 0;
    if (_emptyStreak >= 3) _lastAnnounced = null; // note removed from view

    final counts = <String, int>{};
    for (final l in _history) {
      if (l != null) counts[l] = (counts[l] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    if (top.value >= minVotes && top.key != _lastAnnounced) {
      _lastAnnounced = top.key;
      return Note.parse(top.key);
    }
    return null;
  }

  void reset() {
    _history.clear();
    _lastAnnounced = null;
  }
}
