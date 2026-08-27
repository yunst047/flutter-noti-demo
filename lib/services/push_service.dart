import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
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

  // This isolate shares nothing with the one running the app, so the plugin
  // instance from main() does not exist here and has to be rebuilt. The
  // channels themselves already exist — they are owned by the OS, not the
  // isolate — so demo_high can be reused as-is.
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
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
    });

    // Terminated: the tap that launched the process is delivered only here.
    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      NotiLog.instance.add('push', 'opened from terminated', _describe(initial));
    }
  }

  /// A data-only message displays nothing by itself — the app must post a local
  /// notification. That is the whole trade-off being demonstrated: full control
  /// over the UI, at the cost of the OEM being free to kill the process first.
  void _onForegroundMessage(RemoteMessage m) {
    NotiLog.instance.add('push', 'foreground', _describe(m));

    if (m.notification == null && m.data.isNotEmpty) {
      _localNoti.showFromPush(
        title: m.data['title'] ?? 'Data message',
        body: m.data['body'] ?? jsonEncode(m.data),
      );
    }
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
