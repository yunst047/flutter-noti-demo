import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notidemo/services/noti_log.dart';

void main() {
  setUp(NotiLog.instance.clear);

  test('NotiLog records events newest first', () {
    NotiLog.instance.add('local', 'showNow', 'id=1');
    NotiLog.instance.add('tap', 'body', 'id=1');

    final events = NotiLog.instance.events;
    expect(events, hasLength(2));
    expect(events.first.action, 'body', reason: 'newest event should be first');
    expect(events.last.action, 'showNow');
  });

  test('NotiLog is bounded so the repeating demo cannot grow it forever', () {
    for (var i = 0; i < 350; i++) {
      NotiLog.instance.add('local', 'tick', '$i');
    }
    expect(NotiLog.instance.events.length, lessThanOrEqualTo(300));
    // Oldest entries are the ones dropped.
    expect(NotiLog.instance.events.first.detail, '349');
  });

  test('NotiLog notifies listeners', () {
    var notified = 0;
    void listener() => notified++;
    NotiLog.instance.addListener(listener);
    addTearDown(() => NotiLog.instance.removeListener(listener));

    NotiLog.instance.add('local', 'showNow', '');
    expect(notified, 1);

    NotiLog.instance.clear();
    expect(notified, 2);
  });

  testWidgets('event timestamps are zero-padded', (tester) async {
    final e = NotiEvent('local', 'showNow', '');
    expect(e.time, matches(RegExp(r'^\d{2}:\d{2}:\d{2}$')));
    expect(const ColorScheme.light().primary, isNotNull);
  });
}
