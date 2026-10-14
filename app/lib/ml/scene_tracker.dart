/// Turns per-frame detections into stable, spatial, spoken information:
/// which objects are really there, where (direction and metres), whether
/// they are in the walking path, and whether they are getting closer.
///
/// Ideas taken from the reference repos (docs/REPO_ANALYSIS.md, section 9):
///  * IoU tracking per class and "is it approaching" from a regression over
///    the box size (jayjmha, Assistance-System-for-the-Blind).
///  * A walking-path region in front of the user instead of "anything big".
///  * Priority classes with lower confidence thresholds, cooldowns and change
///    detection before speaking (Smart Real-Time Multimodal Assistance).
/// Added here: real distances from the phone's tilt and known object sizes,
/// time to contact, and directions that follow how the phone is held.
library;

import 'dart:math' as math;

import 'object_detector.dart';

/// Phone orientation from the accelerometer.
class DevicePose {
  /// Degrees the camera points below the horizon (0 = straight ahead, 90 = at the floor).
  final double pitchDown;

  /// Quarter turns of the phone from upright portrait: 0 upright, 1 top to the
  /// left, 2 upside down, 3 top to the right.
  final int quarter;
  const DevicePose(this.pitchDown, this.quarter);

  static const upright = DevicePose(0, 0);

  /// From accelerometer x, y, z (m/s², reaction to gravity, device axes).
  factory DevicePose.fromAccel(double x, double y, double z) {
    final pitch = math.atan2(z, math.sqrt(x * x + y * y)) * 180 / math.pi;
    final int q;
    if (y.abs() >= x.abs()) {
      q = y >= 0 ? 0 : 2;
    } else {
      q = x >= 0 ? 1 : 3;
    }
    return DevicePose(pitch, q);
  }

  bool get lookingDown => pitchDown > 55;
}

enum Hazard { none, warning, danger }

class Tracked {
  final int id;
  final String label;
  double score;
  Detection box; // world-oriented: x left->right, y top->bottom as the user holds the phone
  Detection frameBox; // the same box in camera-frame coordinates, for drawing
  final List<(double, double)> _sizes = []; // (seconds, ln box height)
  int hits = 1;
  double firstSeen, lastSeen;
  double? distance; // metres
  double bearing = 0; // degrees, negative = left
  double? ttc; // seconds to contact
  bool inPath = false;
  Hazard hazard = Hazard.none;

  Tracked(this.id, this.label, this.score, this.box, this.frameBox, double t)
      : firstSeen = t,
        lastSeen = t;

  bool get confirmed => hits >= 2 || score >= 0.7;
  bool get approaching => ttc != null && ttc! < 8;
}

class SceneTracker {
  /// Horizontal field of view of the camera's long side, in degrees. Typical
  /// 26 mm-equivalent phone main cameras are 65 to 70 degrees.
  final double longSideFov;

  /// Height of the camera above the ground while walking, in metres.
  final double cameraHeight;

  /// Warn about things in the path closer than this (metres).
  double warnDistance;

  SceneTracker({this.longSideFov = 67, this.cameraHeight = 1.3, this.warnDistance = 3.5});

  final List<Tracked> objects = [];
  int _nextId = 0;

  /// Feeds one frame. [frameAspect] is width / height of the upright frame.
  List<Tracked> update(List<Detection> raw, double t, DevicePose pose, double frameAspect) {
    final dets = [
      for (final d in raw)
        if (d.score >= minScoreFor(d.label)) (orient(d, pose.quarter), d)
    ];
    // Field of view in world orientation.
    final portrait = pose.quarter.isEven;
    final aspect = portrait ? frameAspect : 1 / frameAspect; // world width / height
    final (hFov, vFov) = _fovs(aspect);

    final matched = <Tracked>{};
    for (final (d, frameBox) in dets) {
      Tracked? best;
      var bestScore = 0.0;
      for (final o in objects) {
        if (o.label != d.label || matched.contains(o)) continue;
        final iou = _iou(o.box, d);
        final dist = math.sqrt(math.pow(o.box.centerX - d.centerX, 2) + math.pow(_cy(o.box) - _cy(d), 2));
        final s = iou > 0.2 ? iou : (dist < 0.12 ? 0.2 - dist : 0);
        if (s > bestScore) {
          best = o;
          bestScore = s;
        }
      }
      if (best == null) {
        best = Tracked(_nextId++, d.label, d.score, d, frameBox, t);
        objects.add(best);
      } else {
        best
          ..hits += 1
          ..score = best.score * 0.5 + d.score * 0.5
          ..box = d
          ..frameBox = frameBox
          ..lastSeen = t;
      }
      matched.add(best);
      _measure(best, t, pose, hFov, vFov);
    }
    objects.removeWhere((o) => t - o.lastSeen > 1.2);
    for (final o in objects) {
      if (!matched.contains(o)) continue;
      o.hazard = _hazard(o, pose);
    }
    final visible = [for (final o in objects) if (matched.contains(o) && o.confirmed) o];
    visible.sort((a, b) => (a.distance ?? 99).compareTo(b.distance ?? 99));
    return visible;
  }

  void reset() => objects.clear();

  /// Lower thresholds for the things that matter most when walking.
  static double minScoreFor(String label) =>
      _vehicles.contains(label) || label == 'person' ? 0.35 : _obstacles.contains(label) ? 0.42 : 0.5;

  (double, double) _fovs(double aspect) {
    final half = longSideFov * math.pi / 360;
    if (aspect >= 1) {
      final v = 2 * math.atan(math.tan(half) / aspect);
      return (longSideFov, v * 180 / math.pi);
    }
    final h = 2 * math.atan(math.tan(half) * aspect);
    return (h * 180 / math.pi, longSideFov);
  }

  void _measure(Tracked o, double t, DevicePose pose, double hFov, double vFov) {
    final b = o.box;
    final tanH = math.tan(hFov * math.pi / 360), tanV = math.tan(vFov * math.pi / 360);
    o.bearing = math.atan((b.centerX - 0.5) * 2 * tanH) * 180 / math.pi;

    final h = (b.bottom - b.top).clamp(0.01, 1.0);
    final cutTop = b.top < 0.02, cutBottom = b.bottom > 0.98;
    double? bySize;
    final real = knownHeights[o.label];
    if (real != null) {
      bySize = real / (2 * tanV * h);
      if (cutTop && cutBottom) bySize = math.min(bySize, 1.0);
    }
    double? byGround;
    if (pose.quarter == 0 && !cutBottom && _onGround.contains(o.label)) {
      final below = pose.pitchDown + math.atan((b.bottom - 0.5) * 2 * tanV) * 180 / math.pi;
      if (below > 2) byGround = cameraHeight / math.tan(below * math.pi / 180);
    }
    final d = switch ((bySize, byGround)) {
      (final s?, final g?) => math.sqrt(s * g), // they fail differently; the geometric mean is robust
      (final s?, null) => s,
      (null, final g?) => g,
      _ => null,
    };
    o.distance = d?.clamp(0.3, 40.0).toDouble();

    // Time to contact from how fast the box grows: tau = h / (dh/dt).
    o._sizes.add((t, math.log(h)));
    o._sizes.removeWhere((s) => t - s.$1 > 1.6);
    o.ttc = null;
    if (o._sizes.length >= 4 && !(cutTop && cutBottom)) {
      final slope = _slope(o._sizes);
      if (slope > 0.12) o.ttc = 1 / slope;
    }

    // Walking corridor: about 0.9 m wide at the object's distance.
    final left = math.atan((b.left - 0.5) * 2 * tanH), right = math.atan((b.right - 0.5) * 2 * tanH);
    if (o.distance != null) {
      final xl = o.distance! * math.tan(left), xr = o.distance! * math.tan(right);
      o.inPath = xl < 0.45 && xr > -0.45;
    } else {
      o.inPath = b.right > 0.35 && b.left < 0.65;
    }
  }

  Hazard _hazard(Tracked o, DevicePose pose) {
    if (!o.confirmed || pose.lookingDown) return Hazard.none;
    final vehicle = _vehicles.contains(o.label);
    if (!vehicle && !_obstacles.contains(o.label) && o.label != 'person') return Hazard.none;
    // A table or bed filling the view is something you are looking at, not walking into.
    if (_surfaces.contains(o.label) && o.box.area > 0.6) return Hazard.none;
    final d = o.distance ?? (o.box.area > 0.4 ? 1.0 : 6.0);
    final ttc = o.ttc ?? double.infinity;
    if (vehicle && ttc < 2.5) return Hazard.danger;
    if (o.inPath && (d < 1.2 || ttc < 1.5)) return Hazard.danger;
    if (vehicle && ttc < 5) return Hazard.warning;
    if (o.inPath && (d < warnDistance || ttc < 3.5)) return Hazard.warning;
    return Hazard.none;
  }

  static double _cy(Detection d) => (d.top + d.bottom) / 2;

  static double _iou(Detection a, Detection b) {
    final iw = math.max(0.0, math.min(a.right, b.right) - math.max(a.left, b.left));
    final ih = math.max(0.0, math.min(a.bottom, b.bottom) - math.max(a.top, b.top));
    final inter = iw * ih;
    final union = a.area + b.area - inter;
    return union <= 0 ? 0 : inter / union;
  }

  static double _slope(List<(double, double)> pts) {
    final n = pts.length;
    final mx = pts.fold(0.0, (s, p) => s + p.$1) / n, my = pts.fold(0.0, (s, p) => s + p.$2) / n;
    var num = 0.0, den = 0.0;
    for (final p in pts) {
      num += (p.$1 - mx) * (p.$2 - my);
      den += (p.$1 - mx) * (p.$1 - mx);
    }
    return den == 0 ? 0 : num / den;
  }
}

/// Rotates a box from the upright-portrait frame into the orientation the
/// user actually holds the phone in, so "left" is always their left.
Detection orient(Detection d, int quarter) => switch (quarter % 4) {
      1 => Detection(d.label, d.score, d.top, 1 - d.right, d.bottom, 1 - d.left),
      2 => Detection(d.label, d.score, 1 - d.right, 1 - d.bottom, 1 - d.left, 1 - d.top),
      3 => Detection(d.label, d.score, 1 - d.bottom, d.left, 1 - d.top, d.right),
      _ => d,
    };

/// Typical real heights in metres, for distance from box size.
const knownHeights = <String, double>{
  'person': 1.65, 'bicycle': 1.05, 'car': 1.5, 'motorcycle': 1.1, 'bus': 3.0, 'truck': 3.0, 'train': 3.8,
  'traffic light': 0.9, 'fire hydrant': 0.75, 'stop sign': 0.75, 'parking meter': 1.3, 'bench': 0.85,
  'dog': 0.55, 'cat': 0.3, 'horse': 1.6, 'cow': 1.4, 'sheep': 0.8, 'goat': 0.7, 'chair': 0.9, 'couch': 0.85,
  'potted plant': 0.7, 'bed': 0.6, 'dining table': 0.75, 'toilet': 0.75, 'tv': 0.55, 'refrigerator': 1.7,
  'suitcase': 0.65, 'backpack': 0.45, 'umbrella': 1.0, 'laptop': 0.24, 'bottle': 0.25, 'cup': 0.1,
  'cell phone': 0.15, 'book': 0.22, 'microwave': 0.3, 'oven': 0.85, 'sink': 0.2, 'clock': 0.3, 'vase': 0.3,
};

const _vehicles = {'car', 'bus', 'truck', 'motorcycle', 'bicycle', 'train'};
const _obstacles = {
  'chair', 'bench', 'couch', 'dining table', 'potted plant', 'fire hydrant', 'stop sign', 'parking meter',
  'dog', 'horse', 'cow', 'sheep', 'bed', 'toilet', 'suitcase', 'refrigerator', 'traffic light',
};
const _surfaces = {'dining table', 'bed', 'couch'};
const _onGround = {
  'person', 'bicycle', 'car', 'motorcycle', 'bus', 'truck', 'chair', 'bench', 'couch', 'dining table',
  'potted plant', 'fire hydrant', 'dog', 'horse', 'cow', 'sheep', 'bed', 'toilet', 'suitcase', 'refrigerator',
  'parking meter',
};
