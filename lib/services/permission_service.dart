import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// Snapshot of every permission this demo cares about.
class PermissionSnapshot {
  const PermissionSnapshot({
    required this.notifications,
    required this.exactAlarm,
    required this.provisional,
  });

  final PermissionStatus notifications;

  /// Android 12+ gates exact-time scheduling behind a separate, non-runtime
  /// permission. Without it `zonedSchedule` silently drifts by minutes.
  final PermissionStatus? exactAlarm;

  /// iOS only. Provisional authorisation delivers quietly to the notification
  /// centre with no permission prompt at all.
  final bool provisional;

  bool get canPostNotifications => notifications.isGranted;
}

/// Wraps the three separate permission systems this app has to satisfy.
///
/// They behave differently enough that lumping them together hides real bugs:
/// Android 13+ has a runtime prompt, Android 12+ exact alarms are a settings
/// toggle rather than a prompt, and iOS has an extra "provisional" tier that
/// never prompts at all.
class PermissionService {
  PermissionService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  Future<PermissionSnapshot> check() async {
    final notifications = await Permission.notification.status;

    PermissionStatus? exactAlarm;
    if (Platform.isAndroid) {
      exactAlarm = await Permission.scheduleExactAlarm.status;
    }

    return PermissionSnapshot(
      notifications: notifications,
      exactAlarm: exactAlarm,
      provisional: false,
    );
  }

  /// Standard request. On Android 13+ this shows the runtime prompt; below 13
  /// notifications are granted at install time and this resolves immediately.
  Future<bool> requestNotifications() async {
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.requestNotificationsPermission() ?? false;
    }

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    return await ios?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        false;
  }

  /// iOS provisional authorisation — the interesting contrast with the above.
  ///
  /// No prompt is shown. Notifications arrive silently in the notification
  /// centre, and the user is offered "Keep" / "Turn Off" the first time they
  /// see one. Android has no equivalent, so this is a no-op there.
  Future<bool> requestProvisional() async {
    if (!Platform.isIOS) return false;
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    return await ios?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
          provisional: true,
        ) ??
        false;
  }

  /// Android 12+ exact alarms.
  ///
  /// This cannot be granted by a runtime prompt — the user has to toggle it in
  /// system settings, so all we can do is send them there.
  Future<void> openExactAlarmSettings() async {
    if (!Platform.isAndroid) return;
    await Permission.scheduleExactAlarm.request();
  }

  Future<void> openSettings() => openAppSettings();
}
