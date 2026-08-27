import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'noti_log.dart';

/// Handles a notification tap that arrives while the app process is dead.
///
/// This MUST be a top-level function annotated with `@pragma('vm:entry-point')`.
/// Flutter tears down and restarts the isolate in that case, and without the
/// annotation tree-shaking removes this symbol in release builds — the app then
/// crashes when the user taps a notification after a swipe-away.
@pragma('vm:entry-point')
void onBackgroundNotificationResponse(NotificationResponse response) {
  debugPrint('background tap: id=${response.id} payload=${response.payload}');
}

/// Every local notification variant the demo shows.
///
/// IDs are fixed per demo so that re-firing one replaces it in the tray rather
/// than stacking duplicates.
class LocalNotiService {
  LocalNotiService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static const channelHigh = 'demo_high';
  static const channelDefault = 'demo_default';
  static const channelLow = 'demo_low';
  static const channelProgress = 'demo_progress';
  static const channelCall = 'demo_call';

  bool _ready = false;

  Future<void> init(void Function(NotificationResponse) onTap) async {
    if (_ready) return;

    // Timezone data must be loaded before any zonedSchedule call, and the
    // device's actual zone must be set — the default is UTC, which would make
    // every scheduled notification fire at the wrong wall-clock time.
    tzdata.initializeTimeZones();
    final localZone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localZone.identifier));

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // Permissions are requested explicitly via PermissionService so the
          // demo can show the difference between standard and provisional.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: onTap,
      onDidReceiveBackgroundNotificationResponse:
          onBackgroundNotificationResponse,
    );

    await _createChannels();
    _ready = true;
  }

  /// Channels are created up front. On Android 8+ a channel's importance is
  /// fixed at creation — changing it in code later has no effect once the
  /// channel exists, which is a common source of "why is it not heads-up".
  Future<void> _createChannels() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;

    const channels = [
      AndroidNotificationChannel(
        channelHigh,
        'High importance',
        description: 'Heads-up banner with sound',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        channelDefault,
        'Default importance',
        description: 'Sound, but no heads-up banner',
        importance: Importance.defaultImportance,
      ),
      AndroidNotificationChannel(
        channelLow,
        'Low importance',
        description: 'Silent, tray only',
        importance: Importance.low,
      ),
      AndroidNotificationChannel(
        channelProgress,
        'Progress',
        description: 'Ongoing progress notifications',
        importance: Importance.low,
      ),
      AndroidNotificationChannel(
        channelCall,
        'Incoming call',
        description: 'Full-screen incoming call style',
        importance: Importance.max,
      ),
    ];

    for (final c in channels) {
      await android.createNotificationChannel(c);
    }
  }

  // ---------------------------------------------------------------- 1. basic

  Future<void> showNow() async {
    await _plugin.show(
      id: 1,
      title: 'Plain notification',
      body: 'Fired immediately from the app',
      notificationDetails: _details(channelHigh),
      payload: 'demo:now',
    );
    NotiLog.instance.add('local', 'showNow', 'id=1');
  }

  // ------------------------------------------------------------ 2. scheduled

  Future<void> scheduleIn(Duration delay) async {
    final when = tz.TZDateTime.now(tz.local).add(delay);
    await _plugin.zonedSchedule(
      id: 2,
      title: 'Scheduled notification',
      body: 'Scheduled ${delay.inSeconds}s ago for now',
      scheduledDate: when,
      notificationDetails: _details(channelHigh),
      // exactAllowWhileIdle fires on time even in Doze. It needs the
      // SCHEDULE_EXACT_ALARM permission on Android 12+; without it Android
      // downgrades the alarm and it can drift by minutes.
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'demo:scheduled',
    );
    NotiLog.instance.add('local', 'scheduleIn', 'fires at $when');
  }

  // ------------------------------------------------------------ 3. repeating

  Future<void> repeatEveryMinute() async {
    await _plugin.periodicallyShow(
      id: 3,
      title: 'Repeating notification',
      body: 'Fires every minute until cancelled',
      repeatInterval: RepeatInterval.everyMinute,
      notificationDetails: _details(channelDefault),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'demo:repeat',
    );
    NotiLog.instance.add('local', 'repeatEveryMinute', 'id=3');
  }

  Future<void> cancel(int id) async {
    await _plugin.cancel(id: id);
    NotiLog.instance.add('local', 'cancel', 'id=$id');
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
    NotiLog.instance.add('local', 'cancelAll', '');
  }

  // ---------------------------------------------------------------- 4. styles

  Future<void> showBigText() async {
    const body =
        'BigTextStyle expands to show the full message when the notification '
        'is pulled down. The collapsed form shows only the first line, which '
        'is why the summary text matters as much as the body.';
    await _plugin.show(
      id: 4,
      title: 'BigText style',
      body: body,
      notificationDetails: NotificationDetails(
        android: const AndroidNotificationDetails(
          channelHigh,
          'High importance',
          styleInformation: BigTextStyleInformation(
            body,
            contentTitle: 'BigText style',
            summaryText: 'Expanded summary line',
          ),
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: 'demo:bigtext',
    );
    NotiLog.instance.add('local', 'bigText', 'id=4');
  }

  Future<void> showInbox() async {
    final lines = [
      'Rider assigned',
      'Restaurant confirmed',
      'Order packed',
      'Out for delivery',
    ];
    await _plugin.show(
      id: 5,
      title: 'Inbox style',
      body: '${lines.length} updates',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelHigh,
          'High importance',
          styleInformation: InboxStyleInformation(
            lines,
            contentTitle: 'Inbox style',
            summaryText: '${lines.length} updates',
          ),
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: 'demo:inbox',
    );
    NotiLog.instance.add('local', 'inbox', 'id=5');
  }

  Future<void> showMessaging() async {
    final me = Person(name: 'You', key: 'me');
    final rider = Person(name: 'Rider', key: 'rider');
    await _plugin.show(
      id: 6,
      title: 'Messaging style',
      body: 'Chat-style thread',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelHigh,
          'High importance',
          styleInformation: MessagingStyleInformation(
            me,
            conversationTitle: 'Delivery chat',
            groupConversation: false,
            messages: [
              Message('I am 5 minutes away', DateTime.now(), rider),
              Message('Great, thanks!', DateTime.now(), me),
            ],
          ),
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: 'demo:messaging',
    );
    NotiLog.instance.add('local', 'messaging', 'id=6');
  }

  // -------------------------------------------------------------- 5. progress

  /// Drives a determinate progress bar 0 → 100 over [steps] updates.
  ///
  /// Reuses one notification ID so the bar animates in place rather than
  /// posting a new notification per tick.
  Future<void> runProgress({int steps = 10}) async {
    for (var i = 0; i <= steps; i++) {
      final pct = (i * 100 / steps).round();
      await _plugin.show(
        id: 7,
        title: 'Downloading',
        body: '$pct%',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelProgress,
            'Progress',
            showProgress: true,
            maxProgress: 100,
            progress: pct,
            ongoing: i < steps,
            onlyAlertOnce: true,
            indeterminate: false,
          ),
          iOS: const DarwinNotificationDetails(presentSound: false),
        ),
        payload: 'demo:progress',
      );
      if (i < steps) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    NotiLog.instance.add('local', 'progress', 'completed 0->100');
  }

  // --------------------------------------------------------------- 6. actions

  Future<void> showWithActions() async {
    await _plugin.show(
      id: 8,
      title: 'Delivery request',
      body: 'Accept this order?',
      notificationDetails: NotificationDetails(
        android: const AndroidNotificationDetails(
          channelHigh,
          'High importance',
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction('accept', 'Accept', showsUserInterface: true),
            AndroidNotificationAction('decline', 'Decline'),
          ],
        ),
        iOS: const DarwinNotificationDetails(categoryIdentifier: 'demo_actions'),
      ),
      payload: 'demo:actions',
    );
    NotiLog.instance.add('local', 'actions', 'id=8');
  }

  // ---------------------------------------------------------- 7. inline reply

  Future<void> showInlineReply() async {
    await _plugin.show(
      id: 9,
      title: 'Rider',
      body: 'I am outside — which gate?',
      notificationDetails: NotificationDetails(
        android: const AndroidNotificationDetails(
          channelHigh,
          'High importance',
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(
              'reply',
              'Reply',
              // RemoteInput is what turns the action into a text field drawn
              // inside the notification shade.
              inputs: <AndroidNotificationActionInput>[
                AndroidNotificationActionInput(label: 'Type a reply'),
              ],
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(categoryIdentifier: 'demo_reply'),
      ),
      payload: 'demo:reply',
    );
    NotiLog.instance.add('local', 'inlineReply', 'id=9');
  }

  // ------------------------------------------------------------- 8. grouping

  /// Posts five children plus a summary.
  ///
  /// The summary must share the group key AND set setGroupSummary, otherwise
  /// Android shows five separate notifications with no collapsed parent.
  Future<void> showGroup() async {
    const groupKey = 'demo.group.orders';

    for (var i = 1; i <= 5; i++) {
      await _plugin.show(
        id: 100 + i,
        title: 'Order #$i',
        body: 'Order #$i was delivered',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelDefault,
            'Default importance',
            groupKey: groupKey,
          ),
          iOS: DarwinNotificationDetails(threadIdentifier: groupKey),
        ),
      );
    }

    await _plugin.show(
      id: 110,
      title: 'Orders',
      body: '5 orders delivered',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          channelDefault,
          'Default importance',
          groupKey: groupKey,
          setAsGroupSummary: true,
        ),
        iOS: DarwinNotificationDetails(threadIdentifier: groupKey),
      ),
    );
    NotiLog.instance.add('local', 'group', '5 + summary');
  }

  // ------------------------------------------------------- 9. channel compare

  Future<void> showOnChannel(String channelId, String label) async {
    await _plugin.show(
      id: 11,
      title: 'Channel: $label',
      body: 'Compare sound and heads-up behaviour between channels',
      notificationDetails: _details(channelId),
      payload: 'demo:channel:$channelId',
    );
    NotiLog.instance.add('local', 'channel', channelId);
  }

  // ------------------------------------------------ 11. full-screen intent

  /// Incoming-call style. Requires USE_FULL_SCREEN_INTENT in the manifest.
  ///
  /// On Android 14+ this permission is only auto-granted to apps whose function
  /// is calling or alarms; other apps must ask the user. When not granted the
  /// notification still posts as a normal heads-up — that is the documented
  /// fallback, not a failure.
  Future<void> showFullScreen() async {
    await _plugin.show(
      id: 12,
      title: 'Incoming call',
      body: 'Rider is calling',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          channelCall,
          'Incoming call',
          priority: Priority.max,
          importance: Importance.max,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.call,
        ),
        iOS: DarwinNotificationDetails(
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
      payload: 'demo:fullscreen',
    );
    NotiLog.instance.add('local', 'fullScreenIntent', 'id=12');
  }

  // ------------------------------------------- 12. iOS interruption levels

  /// iOS only. Android ignores interruptionLevel entirely.
  ///
  /// `critical` additionally needs an entitlement granted by Apple on request;
  /// without it the notification degrades to a normal one rather than erroring.
  Future<void> showInterruptionLevel(InterruptionLevel level) async {
    if (!Platform.isIOS) {
      NotiLog.instance.add(
        'local',
        'interruptionLevel',
        'skipped — iOS only, Android ignores this',
      );
      return;
    }
    await _plugin.show(
      id: 13,
      title: 'Interruption level: ${level.name}',
      body: 'Compare how each level breaks through Focus modes',
      notificationDetails: NotificationDetails(
        iOS: DarwinNotificationDetails(interruptionLevel: level),
      ),
      payload: 'demo:interruption:${level.name}',
    );
    NotiLog.instance.add('local', 'interruptionLevel', level.name);
  }

  NotificationDetails _details(String channelId) => NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      channelId,
      importance: channelId == channelLow
          ? Importance.low
          : Importance.defaultImportance,
    ),
    iOS: const DarwinNotificationDetails(),
  );
}
