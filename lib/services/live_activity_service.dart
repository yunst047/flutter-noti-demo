import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:live_activities/live_activities.dart';
import 'package:live_activities/models/activity_update.dart';

import 'noti_log.dart';

class LiveActivityCapabilities {
  const LiveActivityCapabilities({
    required this.supported,
    required this.enabled,
    required this.allowsPushStart,
  });

  const LiveActivityCapabilities.unsupported()
    : supported = false,
      enabled = false,
      allowsPushStart = false;

  /// iOS 16.1+ and not an iPad — ActivityKit exists at all.
  final bool supported;

  /// Settings → Face ID & Passcode → Live Activities. Off by default on some
  /// configurations, and every request then fails with a permission error that
  /// reads like a bug in the app.
  final bool enabled;

  /// iOS 17.2+. Without it the server cannot *start* an activity, only update
  /// one the app already created.
  final bool allowsPushStart;

  String get summary {
    if (!Platform.isIOS) return 'iOS only — Android uses Live Updates instead';
    if (!supported) return 'ActivityKit unavailable — needs iOS 16.1+ on iPhone';
    if (!enabled) {
      return 'Supported, but Live Activities are switched off in Settings → '
          'Face ID & Passcode';
    }
    return allowsPushStart
        ? 'Full support, including push-to-start (iOS 17.2+)'
        : 'Supported. No push-to-start — the app must create the activity, the '
              'server can only update it';
  }
}

/// iOS Live Activity + Dynamic Island, via ActivityKit.
///
/// The counterpart to [LiveUpdateService] on Android: same four delivery
/// stages, same vocabulary, deliberately different mechanism.
///
/// Note what does *not* travel in the activity's `ContentState`: the fields the
/// widget draws are written into the shared App Group's `UserDefaults` and read
/// back by the extension process. That is the `live_activities` plugin's
/// contract — ActivityKit requires an identical attributes type in both
/// processes, so the plugin ships a fixed one and moves the payload out of band.
class LiveActivityService {
  static const appGroupId = 'group.com.f0h.flt-noti-demo';
  static const _orderId = 'Order #1042';

  static const stages = [
    'Order received',
    'Restaurant is cooking',
    'Rider picked it up',
    'On the way to you',
  ];
  static const etas = ['25 min', '18 min', '12 min', '4 min'];

  static const _baseUrl = String.fromEnvironment('API_BASE_URL');
  static const _apiKey = String.fromEnvironment('API_KEY', defaultValue: 'dev');

  final _plugin = LiveActivities();

  LiveActivityCapabilities capabilities = const LiveActivityCapabilities.unsupported();

  /// The id ActivityKit gave us. Every update and the end call are addressed to
  /// it, so losing it strands a live activity on the Lock Screen.
  String? activityId;

  /// Scoped to one activity and dead the moment it ends — which is why it is
  /// re-sent on every change rather than fetched once. See [pushToStartToken],
  /// which is scoped to the activity *type* and outlives any single activity.
  String? pushToken;
  String? pushToStartToken;

  int stage = 0;

  StreamSubscription<ActivityUpdate>? _updates;
  StreamSubscription<String>? _pushToStart;

  bool get running => activityId != null;

  Future<void> init() async {
    if (!Platform.isIOS) return;

    await _plugin.init(appGroupId: appGroupId);
    await refreshCapabilities();

    // The token can be reissued at any time by the system. Fetching it once
    // after creating the activity is the standard way to end up pushing to a
    // token that has already been replaced.
    _updates = _plugin.activityUpdateStream.listen((update) {
      update.map(
        active: (state) {
          pushToken = state.activityToken;
          NotiLog.instance.add(
            'live',
            'activity token',
            '…${_tail(state.activityToken)}',
          );
          _sendToken('activity', state.activityToken);
        },
        ended: (state) {
          // Distinct from the log line in [end]: this one also fires when the
          // system or the user dismisses the activity behind the app's back.
          NotiLog.instance.add('live', 'activity ended (observed)', state.activityId);
          if (state.activityId == activityId) {
            activityId = null;
            pushToken = null;
          }
        },
        stale: (state) =>
            NotiLog.instance.add('live', 'activity stale', state.activityId),
        unknown: (state) =>
            NotiLog.instance.add('live', 'activity unknown', state.activityId),
      );
    });

    // iOS 17.2+ only, and the stream throws rather than closing when it is not.
    if (capabilities.allowsPushStart) {
      _pushToStart = _plugin.pushToStartTokenUpdateStream.listen((token) {
        pushToStartToken = token;
        NotiLog.instance.add('live', 'push-to-start token', '…${_tail(token)}');
        _sendToken('push-to-start', token);
      }, onError: (Object e) {
        NotiLog.instance.add('live', 'push-to-start unavailable', '$e');
      });
    }
  }

  Future<LiveActivityCapabilities> refreshCapabilities() async {
    if (!Platform.isIOS) {
      capabilities = const LiveActivityCapabilities.unsupported();
      return capabilities;
    }
    final supported = await _plugin.areActivitiesSupported();
    capabilities = LiveActivityCapabilities(
      supported: supported,
      enabled: supported && await _plugin.areActivitiesEnabled(),
      allowsPushStart: supported && await _plugin.allowsPushStart(),
    );
    NotiLog.instance.add(
      'live',
      'capabilities',
      'supported=${capabilities.supported} enabled=${capabilities.enabled} '
          'pushStart=${capabilities.allowsPushStart}',
    );
    return capabilities;
  }

  Map<String, dynamic> _payload(int s) => {
    'orderId': _orderId,
    'stage': s,
    'eta': etas[s],
    'rider': 'Aoy · Honda Wave',
  };

  Future<void> start() async {
    if (!await _guard()) return;
    if (activityId != null) {
      NotiLog.instance.add('live', 'start skipped', 'already running');
      return;
    }
    stage = 0;
    try {
      activityId = await _plugin.createActivity(
        _orderId,
        _payload(0),
        removeWhenAppIsKilled: false,
      );
      NotiLog.instance.add(
        'live',
        'activity started',
        '${activityId ?? '(no id)'} · ${stages[0]}',
      );
    } catch (e) {
      NotiLog.instance.add('live', 'start failed', '$e');
    }
  }

  /// Local update — no server, no push, no token. Worth comparing against the
  /// push-driven path: this one is instant and unthrottled, but only works
  /// while the app itself is running.
  Future<void> update(int s) async {
    if (!await _guard()) return;
    final id = activityId;
    if (id == null) {
      NotiLog.instance.add('live', 'update skipped', 'nothing running');
      return;
    }
    stage = s.clamp(0, stages.length - 1);
    try {
      await _plugin.updateActivity(id, _payload(stage));
      NotiLog.instance.add(
        'live',
        'activity update',
        'stage $stage · ${stages[stage]} · ${etas[stage]}',
      );
    } catch (e) {
      NotiLog.instance.add('live', 'update failed', '$e');
    }
  }

  Future<void> end() async {
    final id = activityId;
    if (id == null) {
      NotiLog.instance.add('live', 'end skipped', 'nothing running');
      return;
    }
    try {
      await _plugin.endActivity(id);
      NotiLog.instance.add('live', 'activity ended', id);
    } catch (e) {
      NotiLog.instance.add('live', 'end failed', '$e');
    }
    // The activity's push token dies with the activity. Keeping it around
    // guarantees a later push fails with a token error that points nowhere.
    activityId = null;
    pushToken = null;
  }

  /// Clears activities left behind by a previous run of the app — ending an
  /// activity is the app's job, and a hot restart does not do it.
  Future<void> endAll() async {
    if (!Platform.isIOS) return;
    await _plugin.endAllActivities();
    activityId = null;
    pushToken = null;
    NotiLog.instance.add('live', 'ended all activities', '');
  }

  Future<void> runLocalSequence({
    Duration gap = const Duration(seconds: 5),
  }) async {
    await start();
    if (activityId == null) return;
    for (var i = 1; i < stages.length; i++) {
      await Future<void>.delayed(gap);
      await update(i);
    }
    await Future<void>.delayed(gap);
    await end();
  }

  Future<bool> _guard() async {
    if (!Platform.isIOS) {
      NotiLog.instance.add('live', 'skipped', 'iOS only');
      return false;
    }
    if (!capabilities.supported || !capabilities.enabled) {
      await refreshCapabilities();
    }
    if (!capabilities.supported || !capabilities.enabled) {
      NotiLog.instance.add('live', 'skipped', capabilities.summary);
      return false;
    }
    return true;
  }

  /// Hands a token to the backend so it can drive the activity by push.
  ///
  /// Both kinds go to the same endpoint with a `kind` discriminator, because
  /// what the server does with them differs entirely: one addresses a running
  /// activity, the other starts a new one.
  Future<void> _sendToken(String kind, String token) async {
    if (_baseUrl.isEmpty) {
      NotiLog.instance.add('live', '$kind token not sent', 'API_BASE_URL not set');
      return;
    }
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/live-activity/token'),
        headers: {'Content-Type': 'application/json', 'X-Demo-Key': _apiKey},
        body: jsonEncode({'kind': kind, 'token': token, 'activityId': activityId}),
      );
      NotiLog.instance.add(
        'live',
        '$kind token ${res.statusCode == 200 ? 'registered' : 'FAILED'}',
        '${res.statusCode}',
      );
    } catch (e) {
      NotiLog.instance.add('live', '$kind token error', '$e');
    }
  }

  String _tail(String t) => t.length <= 12 ? t : t.substring(t.length - 12);

  Future<void> dispose() async {
    await _updates?.cancel();
    await _pushToStart?.cancel();
  }
}
