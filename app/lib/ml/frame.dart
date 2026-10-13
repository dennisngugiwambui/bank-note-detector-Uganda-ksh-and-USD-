/// Turns camera frames into model input. Everything here is pure Dart and
/// isolate-safe, so it runs off the UI thread through `Isolate.run`.
///
/// Preprocessing contract (same as training/data.py):
///   letterbox to SxS, keep the aspect ratio, black padding, centred,
///   raw RGB 0..255. Normalization happens inside the model.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';

/// A copy of a CameraImage that can be sent to another isolate.
class FrameData {
  final int width, height; // sensor orientation
  final int rotation; // degrees clockwise to make the frame upright
  final bool bgra; // iOS: BGRA8888; Android: YUV420
  final List<Uint8List> planes;
  final List<int> rowStrides;
  final List<int> pixelStrides;

  FrameData(this.width, this.height, this.rotation, this.bgra, this.planes,
      this.rowStrides, this.pixelStrides);

  factory FrameData.fromCamera(CameraImage img, int rotation) => FrameData(
        img.width,
        img.height,
        rotation,
        img.format.group == ImageFormatGroup.bgra8888,
        [for (final p in img.planes) Uint8List.fromList(p.bytes)],
        [for (final p in img.planes) p.bytesPerRow],
        [for (final p in img.planes) p.bytesPerPixel ?? 1],
      );

  int get uprightW => (rotation % 180 == 0) ? width : height;
  int get uprightH => (rotation % 180 == 0) ? height : width;

  /// RGB at upright coordinate (u, v), packed as 0xRRGGBB.
  int rgbAt(int u, int v) {
    int sx, sy;
    switch (rotation % 360) {
      case 90:
        sx = v;
        sy = height - 1 - u;
      case 180:
        sx = width - 1 - u;
        sy = height - 1 - v;
      case 270:
        sx = width - 1 - v;
        sy = u;
      default:
        sx = u;
        sy = v;
    }
    if (bgra) {
      final i = sy * rowStrides[0] + sx * 4;
      final p = planes[0];
      return (p[i + 2] << 16) | (p[i + 1] << 8) | p[i];
    }
    final y = planes[0][sy * rowStrides[0] + sx];
    final uvIndex = (sy >> 1) * rowStrides[1] + (sx >> 1) * pixelStrides[1];
    final cb = planes[1][uvIndex] - 128;
    final cr = planes[2][uvIndex] - 128;
    final r = (y + 1.402 * cr).round().clamp(0, 255).toInt();
    final g = (y - 0.344136 * cb - 0.714136 * cr).round().clamp(0, 255).toInt();
    final b = (y + 1.772 * cb).round().clamp(0, 255).toInt();
    return (r << 16) | (g << 8) | b;
  }
}

class ModelInput {
  final Uint8List rgb; // size*size*3
  final int size;
  final double brightness; // mean luma, 0..255
  final double sharpness; // variance of Laplacian on the input image
  ModelInput(this.rgb, this.size, this.brightness, this.sharpness);
}

/// Samples only the output pixels (size^2 lookups), which keeps per-frame
/// cost low even in Dart. With [letterbox] false the frame is stretched to
/// fill the input; detection models (SSD and EfficientDet) expect that.
ModelInput frameToInput(FrameData f, int size, {bool letterbox = true}) {
  final out = Uint8List(size * size * 3); // zeros = black padding
  final uw = f.uprightW, uh = f.uprightH;
  double sx = size / uw, sy = size / uh;
  if (letterbox) sx = sy = math.min(sx, sy);
  final dw = (uw * sx).round(), dh = (uh * sy).round();
  final ox = (size - dw) ~/ 2, oy = (size - dh) ~/ 2;
  for (var y = 0; y < dh; y++) {
    final v = ((y + 0.5) / sy).floor().clamp(0, uh - 1).toInt();
    for (var x = 0; x < dw; x++) {
      final u = ((x + 0.5) / sx).floor().clamp(0, uw - 1).toInt();
      final c = f.rgbAt(u, v);
      final i = ((oy + y) * size + ox + x) * 3;
      out[i] = (c >> 16) & 0xFF;
      out[i + 1] = (c >> 8) & 0xFF;
      out[i + 2] = c & 0xFF;
    }
  }
  final q = quality(out, size, ox, oy, dw, dh);
  return ModelInput(out, size, q.$1, q.$2);
}

/// Mean luma and Laplacian variance over the content area (padding excluded).
(double, double) quality(Uint8List rgb, int size, int ox, int oy, int w, int h) {
  double luma(int x, int y) {
    final i = (y * size + x) * 3;
    return 0.299 * rgb[i] + 0.587 * rgb[i + 1] + 0.114 * rgb[i + 2];
  }

  double sum = 0, lapSum = 0, lapSq = 0;
  int n = 0, m = 0;
  for (var y = oy + 1; y < oy + h - 1; y += 2) {
    for (var x = ox + 1; x < ox + w - 1; x += 2) {
      final c = luma(x, y);
      sum += c;
      n++;
      final lap = luma(x - 1, y) + luma(x + 1, y) + luma(x, y - 1) + luma(x, y + 1) - 4 * c;
      lapSum += lap;
      lapSq += lap * lap;
      m++;
    }
  }
  if (n == 0) return (0, 0);
  final mean = lapSum / m;
  return (sum / n, lapSq / m - mean * mean);
}
