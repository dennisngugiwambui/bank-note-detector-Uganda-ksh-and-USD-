/// Short spoken sentences from tracked objects, nearest first.
library;

import '../core/strings.dart';
import 'scene_tracker.dart';

enum DirectionStyle { simple, clock }

enum DistanceUnit { metres, steps, none }

class SceneSpeech {
  final S s;
  final DirectionStyle direction;
  final DistanceUnit unit;
  const SceneSpeech(this.s, {this.direction = DirectionStyle.simple, this.unit = DistanceUnit.metres});

  String where(double bearing) {
    if (direction == DirectionStyle.clock) {
      final h = bearing.abs() < 15 ? 12 : bearing.abs() < 45 ? (bearing < 0 ? 11 : 1) : (bearing < 0 ? 10 : 2);
      return s.oclock(h);
    }
    if (bearing.abs() < 6) return s.ahead;
    if (bearing.abs() < 15) return bearing < 0 ? s.slightlyLeft : s.slightlyRight;
    return bearing < 0 ? s.left : s.right;
  }

  String? howFar(double? m) => m == null
      ? null
      : switch (unit) {
          DistanceUnit.metres => s.metres(m),
          DistanceUnit.steps => s.steps(m),
          DistanceUnit.none => null,
        };

  /// One object: "chair slightly left, 2 metres, coming towards you".
  String one(Tracked o, {bool withApproach = true}) => [
        '${s.object(o.label)} ${where(o.bearing)}',
        if (o.distance != null && o.distance! < 1.0) s.veryClose else ?howFar(o.distance),
        if (withApproach && o.approaching && o.ttc! < 5) s.approaching,
      ].join(', ');

  /// The urgent message for the most dangerous object.
  String alert(Tracked o) =>
      '${o.hazard == Hazard.danger ? s.stop : s.caution} ${_cap(one(o))}.';

  /// A calm description: up to [max] groups, counted ("2 cars on your left").
  String describe(List<Tracked> objects, {int max = 3, String? sceneGuess}) {
    final groups = <String, List<Tracked>>{};
    for (final o in objects) {
      groups.putIfAbsent('${o.label}|${where(o.bearing)}', () => []).add(o);
    }
    final parts = <String>[];
    for (final g in groups.values) {
      final o = g.first; // nearest, objects arrive sorted by distance
      final name = s.count(g.length, s.object(o.label));
      final far = o.distance != null && o.distance! < 1.0 ? s.veryClose : howFar(o.distance);
      parts.add([
        '$name ${where(o.bearing)}',
        ?far,
      ].join(', '));
      if (parts.length == max) break;
    }
    final known = {for (final o in objects) s.object(o.label)};
    if (sceneGuess != null && parts.length < max && !known.contains(s.object(sceneGuess))) {
      parts.add(parts.isEmpty ? s.looksLike(s.object(sceneGuess)) : s.looksLike(s.object(sceneGuess)).toLowerCase());
    }
    if (parts.isEmpty) return s.nothingRecognized;
    return parts.map(_cap).join('. ');
  }

  /// A key that changes only when what would be said changes meaningfully.
  String signature(List<Tracked> objects) => ([
        for (final o in objects.take(3)) '${o.label}|${where(o.bearing)}|${_bucket(o.distance)}',
      ]..sort())
          .join(';');

  static int _bucket(double? d) => d == null ? -1 : d < 1.5 ? 0 : d < 3 ? 1 : d < 6 ? 2 : 3;

  static String _cap(String t) => t.isEmpty ? t : '${t[0].toUpperCase()}${t.substring(1)}';
}
