import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../main.dart';
import '../services/noti_log.dart';
import '../services/permission_service.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen>
    with WidgetsBindingObserver {
  PermissionSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Exact-alarm permission is granted in system settings, not by a prompt, so
  /// the only way to notice the change is to re-read on resume.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final s = await permissions.check();
    if (mounted) setState(() => _snapshot = s);
  }

  @override
  Widget build(BuildContext context) {
    final s = _snapshot;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Permissions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: 'Re-read status',
          ),
        ],
      ),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _StatusTile(
                  label: 'Notifications',
                  value: s.notifications.name,
                  ok: s.notifications.isGranted,
                ),
                if (Platform.isAndroid)
                  _StatusTile(
                    label: 'Exact alarms (Android 12+)',
                    value: s.exactAlarm?.name ?? 'n/a',
                    ok: s.exactAlarm?.isGranted ?? false,
                  ),
                const SizedBox(height: 24),

                FilledButton.icon(
                  icon: const Icon(Icons.notifications),
                  label: const Text('Request notification permission'),
                  onPressed: () async {
                    final granted = await permissions.requestNotifications();
                    NotiLog.instance.add(
                      'permission',
                      'requestNotifications',
                      'granted=$granted',
                    );
                    await _refresh();
                  },
                ),
                const SizedBox(height: 8),

                if (Platform.isIOS)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.notifications_paused_outlined),
                    label: const Text('Request PROVISIONAL (iOS)'),
                    onPressed: () async {
                      final granted = await permissions.requestProvisional();
                      NotiLog.instance.add(
                        'permission',
                        'requestProvisional',
                        'granted=$granted',
                      );
                      await _refresh();
                    },
                  ),

                if (Platform.isAndroid)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.alarm),
                    label: const Text('Request exact alarm permission'),
                    onPressed: () async {
                      await permissions.openExactAlarmSettings();
                      await _refresh();
                    },
                  ),

                const SizedBox(height: 8),
                TextButton.icon(
                  icon: const Icon(Icons.settings),
                  label: const Text('Open app settings'),
                  onPressed: permissions.openSettings,
                ),

                const SizedBox(height: 24),
                const _Explainer(),
              ],
            ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.label,
    required this.value,
    required this.ok,
  });

  final String label;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: Icon(
        ok ? Icons.check_circle : Icons.cancel,
        color: ok ? Colors.green : Theme.of(context).colorScheme.error,
      ),
      title: Text(label),
      subtitle: Text(value),
    ),
  );
}

class _Explainer extends StatelessWidget {
  const _Explainer();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Why three separate things', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              'Notifications: a runtime prompt on Android 13+. Below 13 it is '
              'granted at install and the request resolves instantly.\n\n'
              'Exact alarms: Android 12+ only, and NOT a prompt — the user has '
              'to toggle it in system settings. Without it, scheduled '
              'notifications still fire but can drift by minutes in Doze.\n\n'
              'Provisional (iOS): no prompt at all. Notifications arrive quietly '
              'in the notification centre and the user chooses Keep or Turn Off '
              'the first time they see one. Android has no equivalent.',
              style: style,
            ),
          ],
        ),
      ),
    );
  }
}
