import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ActivityKind { note, authenticity, obstacle, system }

enum Severity { info, success, warning, danger }

class ActivityEvent {
  final ActivityKind kind;
  final Severity severity;
  final String title;
  final String detail;
  final DateTime time;
  bool read;

  ActivityEvent({
    required this.kind,
    required this.title,
    this.detail = '',
    this.severity = Severity.info,
    DateTime? time,
    this.read = false,
  }) : time = time ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'k': kind.index,
        's': severity.index,
        't': title,
        'd': detail,
        'at': time.millisecondsSinceEpoch,
        'r': read,
      };

  factory ActivityEvent.fromJson(Map<String, dynamic> j) => ActivityEvent(
        kind: ActivityKind.values[j['k'] as int],
        severity: Severity.values[j['s'] as int],
        title: j['t'] as String,
        detail: j['d'] as String,
        time: DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
        read: j['r'] as bool,
      );
}

/// The notification centre: every identified note, authenticity verdict and
/// safety alert. Persisted (last [maxEvents]). [alerts] streams events that
/// should pop up as a heads-up banner.
class ActivityStore extends ChangeNotifier {
  static const maxEvents = 300;
  final SharedPreferences _prefs;
  final List<ActivityEvent> events = [];
  final _alerts = StreamController<ActivityEvent>.broadcast();
  final Map<String, num> totals = {};

  ActivityStore._(this._prefs);

  static Future<ActivityStore> load() async {
    final s = ActivityStore._(await SharedPreferences.getInstance());
    final raw = s._prefs.getString('activity');
    if (raw != null) {
      for (final e in jsonDecode(raw) as List) {
        s.events.add(ActivityEvent.fromJson(e as Map<String, dynamic>));
      }
    }
    final t = s._prefs.getString('totals');
    if (t != null) {
      (jsonDecode(t) as Map<String, dynamic>).forEach((k, v) => s.totals[k] = v as num);
    }
    return s;
  }

  Stream<ActivityEvent> get alerts => _alerts.stream;
  int get unread => events.where((e) => !e.read).length;

  void add(ActivityEvent e, {bool popUp = false}) {
    events.insert(0, e);
    if (events.length > maxEvents) events.removeRange(maxEvents, events.length);
    if (popUp) _alerts.add(e);
    _persist();
  }

  void addToTotal(String currency, num value) {
    totals[currency] = (totals[currency] ?? 0) + value;
    _persist();
  }

  void clearTotals() {
    totals.clear();
    _persist();
  }

  void markAllRead() {
    for (final e in events) {
      e.read = true;
    }
    _persist();
  }

  void clear() {
    events.clear();
    _persist();
  }

  void remove(ActivityEvent e) {
    events.remove(e);
    _persist();
  }

  /// Puts back an event removed by mistake (swipe "Undo").
  void restore(ActivityEvent e, int index) {
    events.insert(index.clamp(0, events.length), e);
    _persist();
  }

  void _persist() {
    _prefs.setString('activity', jsonEncode([for (final e in events) e.toJson()]));
    _prefs.setString('totals', jsonEncode(totals));
    notifyListeners();
  }

  @override
  void dispose() {
    _alerts.close();
    super.dispose();
  }
}
