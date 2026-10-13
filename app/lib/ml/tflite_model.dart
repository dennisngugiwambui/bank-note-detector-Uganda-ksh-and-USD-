import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Thin wrapper over tflite_flutter. It runs inference in a background
/// isolate, accepts uint8 or float32 inputs, and returns every output
/// flattened and dequantized as `List<double>`.
class TfliteModel {
  final Interpreter _interpreter;
  final IsolateInterpreter _isolate;
  final Tensor _input;
  final List<Tensor> _outputs;

  /// Detection models trained in float expect (x-127.5)/127.5. Our own models
  /// normalize internally, so they take raw 0..255 values.
  final bool normalizeFloatInput;

  TfliteModel._(this._interpreter, this._isolate, this._input, this._outputs, this.normalizeFloatInput);

  /// Returns null if the asset is missing or fails to load, so the app can
  /// still run with the features whose models are present.
  static Future<TfliteModel?> load(String asset,
      {bool useGpu = false, bool normalizeFloatInput = false}) async {
    try {
      final options = InterpreterOptions()..threads = 4;
      if (useGpu && Platform.isAndroid) options.addDelegate(GpuDelegateV2());
      final interpreter = await Interpreter.fromAsset(asset, options: options);
      interpreter.allocateTensors();
      final isolate = await IsolateInterpreter.create(address: interpreter.address);
      return TfliteModel._(interpreter, isolate, interpreter.getInputTensor(0),
          interpreter.getOutputTensors(), normalizeFloatInput);
    } catch (e) {
      if (useGpu) return load(asset, normalizeFloatInput: normalizeFloatInput); // fall back to CPU
      debugPrint('Could not load $asset: $e');
      return null;
    }
  }

  int get inputHeight => _input.shape[1];
  int get inputWidth => _input.shape[2];
  List<List<int>> get outputShapes => [for (final t in _outputs) t.shape];

  /// [rgb]: H*W*3 bytes in 0..255, matching the input shape.
  Future<List<List<double>>> run(Uint8List rgb) async {
    final Object input;
    if (_input.type == TensorType.float32) {
      final f = Float32List(rgb.length);
      for (var i = 0; i < rgb.length; i++) {
        f[i] = normalizeFloatInput ? (rgb[i] - 127.5) / 127.5 : rgb[i].toDouble();
      }
      input = f.buffer.asUint8List();
    } else {
      input = rgb; // uint8 model: camera bytes go straight in
    }
    final outputs = <int, Object>{
      for (var i = 0; i < _outputs.length; i++) i: _zeros(_outputs[i].shape, _isFloat(_outputs[i])),
    };
    await _isolate.runForMultipleInputs([input], outputs);
    return [
      for (var i = 0; i < _outputs.length; i++) _dequantize(_flatten(outputs[i]!), _outputs[i]),
    ];
  }

  void close() {
    _isolate.close();
    _interpreter.close();
  }

  static bool _isFloat(Tensor t) => t.type == TensorType.float32;

  static Object _zeros(List<int> shape, bool isFloat) {
    if (shape.length == 1) {
      return isFloat ? List<double>.filled(shape[0], 0.0) : List<int>.filled(shape[0], 0);
    }
    return List.generate(shape[0], (_) => _zeros(shape.sublist(1), isFloat));
  }

  static List<num> _flatten(Object o) {
    if (o is List<num>) return o;
    return [for (final e in o as List) ..._flatten(e as Object)];
  }

  static List<double> _dequantize(List<num> v, Tensor t) {
    if (_isFloat(t)) return [for (final x in v) x.toDouble()];
    final scale = t.params.scale, zero = t.params.zeroPoint;
    return [for (final x in v) scale == 0 ? x.toDouble() : (x - zero) * scale];
  }
}
