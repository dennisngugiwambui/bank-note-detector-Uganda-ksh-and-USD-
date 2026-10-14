import 'package:flutter/foundation.dart';

/// Lets any widget start a voice command ("press and hold anywhere") without
/// knowing about the shell, which owns navigation and registers [handler].
class CommandCenter {
  CommandCenter._();
  static final instance = CommandCenter._();

  Future<void> Function()? handler;

  /// True while listening, for the microphone indicator.
  final listening = ValueNotifier<bool>(false);

  Future<void> listen() async => handler?.call();
}
