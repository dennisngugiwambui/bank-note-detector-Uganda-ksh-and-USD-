import 'dart:async';

import 'package:sensors_plus/sensors_plus.dart';

import '../ml/scene_tracker.dart';

/// Phone tilt and rotation from the accelerometer, smoothed. Used for real
/// distances (camera height and tilt) and so "left" means the user's left
/// however the phone is held.
class PoseSensor {
  StreamSubscription<AccelerometerEvent>? _sub;
  double _x = 0, _y = 9.8, _z = 0;
  DevicePose current = DevicePose.upright;

  void start() {
    _sub ??= accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen((e) {
      const k = 0.15; // low-pass: walking shakes the phone
      _x += (e.x - _x) * k;
      _y += (e.y - _y) * k;
      _z += (e.z - _z) * k;
      current = DevicePose.fromAccel(_x, _y, _z);
    }, onError: (_) {}, cancelOnError: false);
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }
}
