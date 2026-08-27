import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import 'local_noti_service.dart';
import 'noti_log.dart';

/// Handles a push that arrives while the app is in the background or killed.
///
/// MUST be a top-level function with `@pragma('vm:entry-point')`: Flutter spins
/// up a *separate* isolate for it, and without the annotation tree-shaking
/// removes the symbol in release builds. That isolate shares no state with the
/// running app, which is why Firebase has to be initialised again inside it.
@pragma('vm:entry-point')
Future<void> onBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('background push: ${message.messageId} data=${message.data}');

  // A data-only message displays nothing on its own. In the foreground the app
  // draws it; without this, backgrounding the app made data-only pushes vanish
  // silently even though they were delivered — which is the failure mode this
  // demo exists to make visible, not to reproduce by accident.
  if (message.notification != null || message.data.isEmpty) return;

  // Dispatch on type exactly as the foreground handler does.
  //
  // Without this the isolate fell through to the generic branch below, whose
  // body is jsonEncode(data) — so a silent push, which by definition carries no
  // display text, rendered its own raw payload on screen:
  //   {"type":"silent_fetch","fetchPath":"/api/inbox"}
  // Correct in the foreground, garbage in the background.
  switch (message.data['type']) {
    case 'silent_fetch':
      await _backgroundSilentFetch(
        message.data['fetchPath'] ?? '/api/inbox',
      );
      return;
    case 'deeplink':
      // The OS already drew the notification message; the route is handled on
      // tap, so there is nothing to display here.
      return;

    case 'delivery_step':
      // Drives the Live Update rather than posting a notification. The
      // MethodChannel is addressed directly because this isolate has no access
      // to the LiveUpdateService instance main() created.
      await _backgroundDeliveryStep(message.data);
      return;
  }

  // This isolate shares nothing with the one running the app, so the plugin
  // instance from main() does not exist here and has to be rebuilt. The
  // channels themselves already exist — they are owned by the OS, not the
  // isolate — so demo_high can be reused as-is.
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_notification'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ),
  );

  await plugin.show(
    id: 21,
    title: message.data['title'] ?? 'Data message',
    body: message.data['body'] ?? jsonEncode(message.data),
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        LocalNotiService.channelHigh,
        'High importance',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    ),
    payload: 'push:data:background',
  );
}

/// Silent-push fetch, running in the background isolate.
///
/// Duplicated rather than shared with PushService.handleSilentFetch because
/// that instance does not exist here — the isolate has its own memory and no
/// access to anything main() constructed. The compile-time dart-defines below
/// ARE available, since they are baked in at build time rather than held in
/// instance state.
@pragma('vm:entry-point')
Future<void> _backgroundSilentFetch(String path) async {
  const baseUrl = String.fromEnvironment('API_BASE_URL');
  const apiKey = String.fromEnvironment('API_KEY', defaultValue: 'dev');
  if (baseUrl.isEmpty) return;

  try {
    final res = await http.get(
      Uri.parse('$baseUrl$path'),
      headers: {'X-Demo-Key': apiKey},
    );
    if (res.statusCode != 200) {
      debugPrint('background silent fetch failed: HTTP ${res.statusCode}');
      return;
    }
    final items = (jsonDecode(res.body) as Map<String, dynamic>)['items'] as List;

    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );

    for (var i = 0; i < items.length; i++) {
      final item = items[i] as Map<String, dynamic>;
      await plugin.show(
        id: 22 + i,
        title: item['title'] as String? ?? 'Inbox',
        body: item['body'] as String? ?? '',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            LocalNotiService.channelHigh,
            'High importance',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: 'push:silent:background',
      );
    }
    debugPrint('background silent fetch: displayed ${items.length} item(s)');
  } catch (e) {
    debugPrint('background silent fetch error: $e');
  }
}

/// Advances the Android Live Update from the background isolate.
@pragma('vm:entry-point')
Future<void> _backgroundDeliveryStep(Map<String, dynamic> data) async {
  if (!Platform.isAndroid) return;
  const channel = MethodChannel('noti_demo/live_update');
  final index = int.tryParse('${data['index'] ?? '1'}') ?? 1;
  try {
    await channel.invokeMethod<void>(index <= 1 ? 'start' : 'update', {
      'step': index - 1,
      'title': 'Order ${data['orderId'] ?? ''}',
      'eta': '${data['eta'] ?? ''}',
    });
    debugPrint('background delivery step $index applied');
  } catch (e) {
    debugPrint('background delivery step failed: $e');
  }
}

class PushService {
  PushService(this._localNoti);

  final LocalNotiService _localNoti;

  static const _baseUrl = String.fromEnvironment('API_BASE_URL');
  static const _apiKey = String.fromEnvironment('API_KEY', defaultValue: 'dev');

  String? token;
  bool subscribedToTopic = false;

  /// A stable per-install identifier so the backend can target one device.
  ///
  /// Derived from the FCM token rather than a device ID: no extra permissions,
  /// and it changes if the app is reinstalled, which is exactly when the old
  /// token stops working anyway.
  String get deviceId {
    final t = token;
    if (t == null || t.length < 12) return 'unknown';
    return '${Platform.isAndroid ? 'android' : 'ios'}-${t.substring(t.length - 8)}';
  }

  Future<void> init() async {
    await Firebase.initializeApp();

    FirebaseMessaging.onBackgroundMessage(onBackgroundMessage);

    final messaging = FirebaseMessaging.instance;

    // Without this, iOS shows nothing at all while the app is foregrounded and
    // it looks like the push never arrived.
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    token = await messaging.getToken();
    NotiLog.instance.add(
      'push',
      'token acquired',
      token == null ? 'NULL — no Play Services?' : '…${token!.substring(token!.length - 12)}',
    );
    if (token != null) await register();

    // Tokens rotate: on reinstall, restore to a new device, or when Firebase
    // decides to. Fetching once at startup and never again is the standard way
    // to end up pushing to a dead token.
    messaging.onTokenRefresh.listen((t) async {
      token = t;
      NotiLog.instance.add('push', 'token refreshed', '…${t.substring(t.length - 12)}');
      await register();
    });

    // Foreground.
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // Background, notification tapped.
    FirebaseMessaging.onMessageOpenedApp.listen((m) {
      NotiLog.instance.add('push', 'opened from background', _describe(m));
      _route(m);
    });

    // Terminated: the tap that launched the process is delivered only here, and
    // nowhere else. Skipping this call loses precisely the deep link users
    // notice — the one that opened the app from cold.
    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      NotiLog.instance.add('push', 'opened from terminated', _describe(initial));
      _route(initial);
    }
  }

  /// Where a deep link should navigate to. Set by main() so this service does
  /// not need to know about the router.
  void Function(String route)? onDeepLink;

  /// Server-driven delivery step. Wired in main() to the Live Update service,
  /// so this class stays unaware of the platform channel.
  Future<void> Function(Map<String, dynamic> data)? onDeliveryStep;

  void _route(RemoteMessage m) {
    final route = routeFor(m);
    if (route == null) return;
    NotiLog.instance.add('push', 'deep link', route);
    onDeepLink?.call(route);
  }

  /// A data-only message displays nothing by itself — the app must post a local
  /// notification. That is the whole trade-off being demonstrated: full control
  /// over the UI, at the cost of the OEM being free to kill the process first.
  Future<void> _onForegroundMessage(RemoteMessage m) async {
    NotiLog.instance.add('push', 'foreground', _describe(m));

    switch (m.data['type']) {
      // Phase 3: carries no content, only a signal to go and fetch.
      case 'silent_fetch':
        await handleSilentFetch(m.data['fetchPath'] ?? '/api/inbox');
        return;
      // Buttons cannot ride on a notification message — the OS draws those and
      // ignores anything the app would attach — so this arrives as data and is
      // rebuilt locally with actions.
      case 'actions':
        await _localNoti.showWithActions();
        return;

      // Server-driven delivery steps drive the Live Update, they do not post a
      // notification of their own. The payload carries a title but no body, so
      // falling through to the generic branch rendered jsonEncode(data) — the
      // raw payload — on screen once per step.
      case 'delivery_step':
        await onDeliveryStep?.call(m.data);
        return;
    }

    if (m.notification == null && m.data.isNotEmpty) {
      _localNoti.showFromPush(
        title: m.data['title'] ?? 'Data message',
        body: m.data['body'] ?? jsonEncode(m.data),
      );
    }
  }

  /// Silent push → fetch → display.
  ///
  /// The content never travels through FCM. It therefore cannot go stale
  /// between send and display, is not bound by the 4KB payload cap, and is not
  /// visible to Google in transit. This is the pattern production apps actually
  /// use, and the reason silent push exists.
  Future<void> handleSilentFetch(String path) async {
    if (_baseUrl.isEmpty) {
      NotiLog.instance.add('push', 'silent fetch skipped', 'API_BASE_URL not set');
      return;
    }
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl$path'),
        headers: {'X-Demo-Key': _apiKey},
      );
      if (res.statusCode != 200) {
        NotiLog.instance.add('push', 'silent fetch failed', 'HTTP ${res.statusCode}');
        return;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final items = (body['items'] as List).cast<dynamic>();
      NotiLog.instance.add('push', 'silent fetch ok', '${items.length} item(s) from $path');

      for (final raw in items) {
        final item = raw as Map<String, dynamic>;
        await _localNoti.showFromPush(
          title: item['title'] as String? ?? 'Inbox',
          body: item['body'] as String? ?? '',
        );
      }
    } catch (e) {
      NotiLog.instance.add('push', 'silent fetch error', '$e');
    }
  }

  /// Route a deep link carried in `data`.
  ///
  /// The route travels in `data` rather than `notification` because data
  /// survives on every platform and in every app state. If it rode only in the
  /// notification block, the OS would draw the message and hand the app nothing
  /// to route with.
  String? routeFor(RemoteMessage m) {
    final route = m.data['route'];
    return (route is String && route.startsWith('/')) ? route : null;
  }

  String _describe(RemoteMessage m) {
    final kind = m.notification != null ? 'notification' : 'data-only';
    return '$kind id=${m.messageId ?? '-'} data=${jsonEncode(m.data)}';
  }

  /// Sends the token to the backend so it can be pushed to later.
  Future<void> register() async {
    final t = token;
    if (t == null) return;
    if (_baseUrl.isEmpty) {
      NotiLog.instance.add('push', 'register skipped', 'API_BASE_URL not set');
      return;
    }
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/tokens'),
        headers: {'Content-Type': 'application/json', 'X-Demo-Key': _apiKey},
        body: jsonEncode({
          'deviceId': deviceId,
          'token': t,
          'platform': Platform.isAndroid ? 'android' : 'ios',
        }),
      );
      NotiLog.instance.add(
        'push',
        'register ${res.statusCode == 200 ? 'ok' : 'FAILED'}',
        '${res.statusCode} deviceId=$deviceId',
      );
    } catch (e) {
      NotiLog.instance.add('push', 'register error', '$e');
    }
  }

  Future<void> toggleTopic() async {
    const topic = 'demo-all';
    final messaging = FirebaseMessaging.instance;
    if (subscribedToTopic) {
      await messaging.unsubscribeFromTopic(topic);
    } else {
      await messaging.subscribeToTopic(topic);
    }
    subscribedToTopic = !subscribedToTopic;
    NotiLog.instance.add(
      'push',
      subscribedToTopic ? 'subscribed' : 'unsubscribed',
      topic,
    );
  }

  /// Asks the backend to push to this device. The app never sends FCM traffic
  /// itself — that would need the server key on the device.
  Future<void> requestPush(String endpoint, {Map<String, dynamic>? extra}) async {
    if (_baseUrl.isEmpty) {
      NotiLog.instance.add('push', 'request skipped', 'API_BASE_URL not set');
      return;
    }
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl$endpoint'),
        headers: {'Content-Type': 'application/json', 'X-Demo-Key': _apiKey},
        body: jsonEncode({
          'deviceId': deviceId,
          'title': 'Hello from the server',
          'body': 'Sent via $endpoint',
          ...?extra,
        }),
      );
      NotiLog.instance.add(
        'push',
        'requested $endpoint',
        '${res.statusCode} ${res.body.length > 160 ? '${res.body.substring(0, 160)}…' : res.body}',
      );
    } catch (e) {
      NotiLog.instance.add('push', 'request error', '$e');
    }
  }

  String get backendLabel => _baseUrl.isEmpty ? '(API_BASE_URL not set)' : _baseUrl;
}
