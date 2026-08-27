import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

import 'screens/home_screen.dart';
import 'screens/live_update_screen.dart';
import 'screens/local_noti_screen.dart';
import 'screens/log_screen.dart';
import 'screens/permission_screen.dart';
import 'screens/push_screen.dart';
import 'services/live_update_service.dart';
import 'services/local_noti_service.dart';
import 'services/noti_log.dart';
import 'services/permission_service.dart';
import 'services/push_service.dart';

final plugin = FlutterLocalNotificationsPlugin();
final localNoti = LocalNotiService(plugin);
final permissions = PermissionService(plugin);
final push = PushService(localNoti);
final liveUpdate = LiveUpdateService();

final _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
    GoRoute(path: '/permissions', builder: (_, _) => const PermissionScreen()),
    GoRoute(path: '/local', builder: (_, _) => const LocalNotiScreen()),
    GoRoute(path: '/push', builder: (_, _) => const PushScreen()),
    GoRoute(path: '/live', builder: (_, _) => const LiveUpdateScreen()),
    GoRoute(path: '/log', builder: (_, _) => const LogScreen()),
  ],
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await localNoti.init(_onNotificationTap);

  // A tap that launched the app from a cold start is not delivered to the
  // callback above — it has to be pulled out explicitly, or the deep link is
  // lost exactly in the case users notice most.
  final launch = await plugin.getNotificationAppLaunchDetails();
  if (launch?.didNotificationLaunchApp ?? false) {
    final payload = launch!.notificationResponse?.payload;
    NotiLog.instance.add('tap', 'cold start', payload ?? '(no payload)');
  }

  // Push init is allowed to fail without taking the app down: Phases 0 and 1
  // work with no Firebase at all, and a missing google-services.json should
  // leave the local-notification demos usable rather than showing a black
  // screen.
  // Deep links are routed here rather than inside PushService, so the service
  // stays unaware of the router. Guarded against unknown routes: a payload is
  // attacker-influenced input in principle, and go_router throws on a route it
  // does not recognise.
  push.onDeepLink = (route) {
    const known = {'/', '/permissions', '/local', '/push', '/live', '/log'};
    if (!known.contains(route)) {
      NotiLog.instance.add('push', 'deep link ignored', 'unknown route $route');
      return;
    }
    _router.go(route);
  };

  try {
    await push.init();
  } catch (e) {
    NotiLog.instance.add('push', 'init failed', '$e');
  }

  runApp(const NotiDemoApp());
}

void _onNotificationTap(NotificationResponse response) {
  final input = response.input;
  NotiLog.instance.add(
    'tap',
    response.actionId ?? 'body',
    [
      'id=${response.id}',
      if (response.payload != null) 'payload=${response.payload}',
      // Inline reply text arrives here rather than as a separate callback.
      if (input != null && input.isNotEmpty) 'reply="$input"',
    ].join(' '),
  );
}

class NotiDemoApp extends StatelessWidget {
  const NotiDemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Notification Demo',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorSchemeSeed: const Color(0xFF3B6EF6),
      brightness: Brightness.light,
      useMaterial3: true,
    ),
    darkTheme: ThemeData(
      colorSchemeSeed: const Color(0xFF3B6EF6),
      brightness: Brightness.dark,
      useMaterial3: true,
    ),
    routerConfig: _router,
  );
}
