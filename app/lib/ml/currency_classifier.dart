import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/currency.dart';
import 'tflite_model.dart';

class Prediction {
  final String label;
  final double confidence;

  /// Centred, L2-normalised embedding, when the model exports one.
  final List<double>? features;

  /// True when the answer came from a note the user taught on this phone.
  final bool taught;
  const Prediction(this.label, this.confidence, {this.features, this.taught = false});
}

/// The multi-currency denomination classifier. Output 1 is softmax(logits/T),
/// calibrated during training. Output 2 (optional) is an embedding used to
/// recognise notes the user taught on the phone.
class CurrencyClassifier {
  static const modelAsset = 'assets/currency/model.tflite';
  static const labelsAsset = 'assets/currency/labels.txt';

  final TfliteModel _model;
  final List<String> labels;
  final TaughtNotes taught;
  CurrencyClassifier._(this._model, this.labels, this.taught);

  int get inputSize => _model.inputHeight;
  bool get canLearn => _model.outputShapes.length > 1;

  static Future<CurrencyClassifier?> load() async {
    final model = await TfliteModel.load(modelAsset);
    if (model == null) return null;
    final labels = (await rootBundle.loadString(labelsAsset))
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return CurrencyClassifier._(model, labels, await TaughtNotes.load());
  }

  Future<Prediction> classify(Uint8List rgb) async {
    final outs = await _model.run(rgb);
    // Tell outputs apart by length: probabilities have one value per label.
    final probs = outs.firstWhere((o) => o.length == labels.length, orElse: () => outs.first);
    final feats = outs.length > 1 ? outs.firstWhere((o) => !identical(o, probs)) : null;
    var best = 0;
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > probs[best]) best = i;
    }
    var p = Prediction(labels[best], probs[best], features: feats);
    if (feats != null) {
      final t = taught.match(feats);
      // A taught note wins when it is a clear match; it also overrides
      // "background", since taught notes are often ones the model never saw.
      if (t != null && (t.$2 >= 0.80 || p.label == backgroundLabel || p.confidence < 0.6)) {
        p = Prediction(t.$1, t.$2, features: feats, taught: true);
      }
    }
    return p;
  }

  void close() => _model.close();
}

/// Notes taught on the phone: a few embeddings per label, matched by cosine
/// similarity (k nearest neighbours with a margin over the runner-up label).
class TaughtNotes {
  final File? _file;
  final Map<String, List<List<double>>> examples;
  TaughtNotes(this._file, this.examples);

  /// Cosine similarity needed to accept a match.
  static const minSimilarity = 0.72;

  /// The best label must beat the best other label by this much.
  static const margin = 0.05;

  static Future<TaughtNotes> load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/taught_notes.json');
      if (!await f.exists()) return TaughtNotes(f, {});
      final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return TaughtNotes(f, {
        for (final e in raw.entries)
          e.key: [for (final v in e.value as List) (v as List).map((x) => (x as num).toDouble()).toList()],
      });
    } catch (e) {
      debugPrint('taught notes: $e');
      return TaughtNotes(null, {});
    }
  }

  bool get isEmpty => examples.isEmpty;
  int count(String label) => examples[label]?.length ?? 0;

  Future<void> add(String label, List<double> features) async {
    (examples[label] ??= []).add(features);
    if (examples[label]!.length > 40) examples[label]!.removeAt(0);
    await _save();
  }

  Future<void> remove(String label) async {
    examples.remove(label);
    await _save();
  }

  Future<void> _save() async {
    try {
      await _file?.writeAsString(jsonEncode(examples));
    } catch (_) {}
  }

  /// (label, similarity) of the best match, or null.
  (String, double)? match(List<double> f) => matchIn(examples, f);

  static (String, double)? matchIn(Map<String, List<List<double>>> examples, List<double> f) {
    if (examples.isEmpty) return null;
    final scores = <String, double>{};
    for (final e in examples.entries) {
      // Mean of the 3 best similarities: robust to one odd example.
      final sims = [for (final v in e.value) cosine(v, f)]..sort((a, b) => b.compareTo(a));
      final k = math.min(3, sims.length);
      scores[e.key] = sims.take(k).reduce((a, b) => a + b) / k;
    }
    final ranked = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final best = ranked.first;
    final second = ranked.length > 1 ? ranked[1].value : -1.0;
    if (best.value < minSimilarity || best.value - second < margin) return null;
    return (best.key, best.value);
  }

  static double cosine(List<double> a, List<double> b) {
    var dot = 0.0, na = 0.0, nb = 0.0;
    for (var i = 0; i < a.length && i < b.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    return na == 0 || nb == 0 ? 0 : dot / math.sqrt(na * nb);
  }
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

  /// Stricter settings for Objects mode, where the camera is not aimed at money.
  factory PredictionSmoother.background(double threshold) =>
      PredictionSmoother(threshold: math.max(threshold, 0.92), window: 6, minVotes: 5);

  /// Returns a note when it should be announced now.
  Note? add(Prediction p) {
    final note = p.confidence >= threshold ? Note.parse(p.label) : null;
    _history.add(note?.label);
    if (_history.length > window) _history.removeAt(0);

    // Only a confident "no money" clears the last note, so a shaky hand does
    // not make the same note be announced twice.
    final isBackground = p.label == backgroundLabel && p.confidence >= 0.6;
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
    _emptyStreak = 0;
  }
}
