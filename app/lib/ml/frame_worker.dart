import 'dart:async';
import 'dart:isolate';

import 'frame.dart';

/// One long-lived background isolate that turns camera frames into model
/// inputs. `compute()` spawned a new isolate for every frame and copied the
/// image twice; here the planes are handed over with TransferableTypedData
/// and every input size the frame needs is made in one pass.
class FrameWorker {
  final SendPort _send;
  final ReceivePort _recv;
  final Isolate _isolate;
  final _pending = <int, Completer<List<ModelInput>>>{};
  int _next = 0;

  FrameWorker._(this._send, this._recv, this._isolate) {
    _recv.listen((msg) {
      final (int id, List<ModelInput> out) = msg as (int, List<ModelInput>);
      _pending.remove(id)?.complete(out);
    });
  }

  static Future<FrameWorker> start() async {
    final recv = ReceivePort();
    final ready = Completer<SendPort>();
    late final StreamSubscription<dynamic> sub;
    final boot = ReceivePort();
    sub = boot.listen((m) {
      ready.complete(m as SendPort);
      sub.cancel();
      boot.close();
    });
    final iso = await Isolate.spawn(_main, (boot.sendPort, recv.sendPort), debugName: 'frame-worker');
    return FrameWorker._(await ready.future, recv, iso);
  }

  /// [specs]: (size, letterbox) per wanted input.
  Future<List<ModelInput>> prepare(FrameData f, List<(int, bool)> specs) {
    final id = _next++;
    final c = Completer<List<ModelInput>>();
    _pending[id] = c;
    _send.send((
      id,
      f.width,
      f.height,
      f.rotation,
      f.bgra,
      [for (final p in f.planes) TransferableTypedData.fromList([p])],
      f.rowStrides,
      f.pixelStrides,
      specs,
    ));
    return c.future;
  }

  void close() {
    for (final c in _pending.values) {
      c.completeError(StateError('worker closed'));
    }
    _pending.clear();
    _recv.close();
    _isolate.kill(priority: Isolate.immediate);
  }

  static void _main((SendPort, SendPort) ports) {
    final inbox = ReceivePort();
    ports.$1.send(inbox.sendPort);
    inbox.listen((msg) {
      final (
        int id,
        int w,
        int h,
        int rot,
        bool bgra,
        List<TransferableTypedData> planes,
        List<int> rows,
        List<int> pix,
        List<(int, bool)> specs,
      ) = msg as (int, int, int, int, bool, List<TransferableTypedData>, List<int>, List<int>, List<(int, bool)>);
      final f = FrameData(
          w, h, rot, bgra, [for (final p in planes) p.materialize().asUint8List()], rows, pix);
      ports.$2.send((id, [for (final (size, lb) in specs) frameToInput(f, size, letterbox: lb)]));
    });
  }
}
