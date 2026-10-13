import 'package:flutter/widgets.dart';

import '../scan_controller.dart';
import 'activity.dart';
import 'auth.dart';
import 'settings.dart';

/// Gives every screen access to the app's services without a state-management
/// package. Swap implementations (e.g. a cloud AuthService) in main.dart.
class AppScope extends InheritedWidget {
  final AppSettings settings;
  final AuthService auth;
  final ActivityStore activity;
  final ScanController scan;

  const AppScope({
    super.key,
    required this.settings,
    required this.auth,
    required this.activity,
    required this.scan,
    required super.child,
  });

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}
