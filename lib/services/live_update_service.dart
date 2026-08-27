import 'dart:io';

import 'package:flutter/services.dart';

import 'noti_log.dart';

class LiveUpdateCapabilities {
  const LiveUpdateCapabilities({
    required this.sdkInt,
    required this.sdkIntFull,
    required this.supportsProgressStyle,
    required this.canPostPromoted,
  });

  const LiveUpdateCapabilities.unsupported()
    : sdkInt = 0,
      sdkIntFull = 0,
      supportsProgressStyle = false,
      canPostPromoted = false;

  final int sdkInt;

  /// Encodes major and minor: 36.1 arrives as 3600001.
  ///
  /// This is the only way to tell Android 16 from Android 16 QPR1 — [sdkInt]
  /// reports 36 for both, and promotion only works on the latter.
  final int sdkIntFull;

  final bool supportsProgressStyle;
  final bool canPostPromoted;

  bool get isQpr1 => sdkIntFull >= 3600001;

  String get summary {
    if (!Platform.isAndroid) return 'Android only';
    if (!supportsProgressStyle) {
      return 'API $sdkInt — needs API 36+. Falls back to an ordinary ongoing '
          'notification.';
    }
    if (!isQpr1) {
      return 'API $sdkInt — ProgressStyle works, but promotion needs API 36.1 '
          '(Android 16 QPR1). It will update in place without being promoted, '
          'which is correct behaviour.';
    }
    return 'API 36.1 — full Live Updates, promotion included'
        '${canPostPromoted ? '' : ' (but the system currently declines to promote)'}';
  }
}

/// Android Live Updates, via a MethodChannel to LiveUpdatePlugin.kt.
///
/// flutter_local_notifications has no ProgressStyle support, so this is a
/// direct bridge to the platform API.
class LiveUpdateService {
  static const _channel = MethodChannel('noti_demo/live_update');

  LiveUpdateCapabilities capabilities = const LiveUpdateCapabilities.unsupported();

  Future<LiveUpdateCapabilities> refreshCapabilities() async {
    if (!Platform.isAndroid) {
      capabilities = const LiveUpdateCapabilities.unsupported();
      return capabilities;
    }
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>('capabilities');
      capabilities = LiveUpdateCapabilities(
        sdkInt: r?['sdkInt'] as int? ?? 0,
        sdkIntFull: r?['sdkIntFull'] as int? ?? 0,
        supportsProgressStyle: r?['supportsProgressStyle'] as bool? ?? false,
        canPostPromoted: r?['canPostPromoted'] as bool? ?? false,
      );
      NotiLog.instance.add(
        'live',
        'capabilities',
        'sdk=${capabilities.sdkInt} full=${capabilities.sdkIntFull} '
            'promote=${capabilities.canPostPromoted}',
      );
    } on PlatformException catch (e) {
      NotiLog.instance.add('live', 'capabilities failed', '${e.message}');
    }
    return capabilities;
  }

  Future<void> start({String title = 'Order #1042', String eta = '25 min'}) =>
      _invoke('start', {'title': title, 'eta': eta}, 'start');

  Future<void> update({
    required int step,
    String title = 'Order #1042',
    String eta = '',
  }) => _invoke('update', {'step': step, 'title': title, 'eta': eta}, 'update step=$step');

  Future<void> end() => _invoke('end', const {}, 'end');

  Future<void> _invoke(String method, Map<String, dynamic> args, String label) async {
    if (!Platform.isAndroid) {
      NotiLog.instance.add('live', 'skipped', 'Android only');
      return;
    }
    try {
      await _channel.invokeMethod<void>(method, args);
      NotiLog.instance.add('live', label, '');
    } on PlatformException catch (e) {
      NotiLog.instance.add('live', '$label failed', '${e.message}');
    }
  }

  /// Runs the four delivery stages locally, so the progression can be seen
  /// without the backend. The server-driven version arrives in Phase 6.
  Future<void> runLocalSequence({Duration gap = const Duration(seconds: 4)}) async {
    const etas = ['25 min', '18 min', '12 min', '4 min'];
    await start(eta: etas.first);
    for (var i = 1; i < etas.length; i++) {
      await Future<void>.delayed(gap);
      await update(step: i, eta: etas[i]);
    }
    await Future<void>.delayed(gap);
    await end();
  }
}
