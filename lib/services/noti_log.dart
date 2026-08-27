import 'package:flutter/foundation.dart';

class NotiEvent {
  NotiEvent(this.source, this.action, this.detail) : at = DateTime.now();

  /// Where it came from: `local`, `push`, `permission`, `tap`.
  final String source;
  final String action;
  final String detail;
  final DateTime at;

  String get time =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}:'
      '${at.second.toString().padLeft(2, '0')}';
}

/// In-app event log.
///
/// Exists because most notification bugs are invisible from the UI: a payload
/// arrives but nothing is drawn, or a tap is delivered to a handler that never
/// ran. Recording every event with a timestamp makes the difference between
/// "not received" and "received but not displayed" obvious.
class NotiLog extends ChangeNotifier {
  NotiLog._();
  static final instance = NotiLog._();

  final List<NotiEvent> _events = [];
  List<NotiEvent> get events => List.unmodifiable(_events.reversed);

  void add(String source, String action, String detail) {
    _events.add(NotiEvent(source, action, detail));
    // Keep the list bounded; the repeating demo can post indefinitely.
    if (_events.length > 300) _events.removeAt(0);
    debugPrint('[$source] $action ${detail.isEmpty ? '' : '- $detail'}');
    notifyListeners();
  }

  void clear() {
    _events.clear();
    notifyListeners();
  }
}
