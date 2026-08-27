import 'dart:io';

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/live_activity_service.dart';

class LiveActivityScreen extends StatefulWidget {
  const LiveActivityScreen({super.key});

  @override
  State<LiveActivityScreen> createState() => _LiveActivityScreenState();
}

class _LiveActivityScreenState extends State<LiveActivityScreen> {
  bool _running = false;

  @override
  void initState() {
    super.initState();
    liveActivity.refreshCapabilities().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _do(Future<void> Function() action) async {
    await action();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caps = liveActivity.capabilities;
    final ok = caps.supported && caps.enabled;

    return Scaffold(
      appBar: AppBar(title: const Text('Live Activity (iOS)')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: ok
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(ok ? Icons.check_circle : Icons.info_outline, size: 20),
                      const SizedBox(width: 8),
                      Text('This device', style: theme.textTheme.titleSmall),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(caps.summary, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Text(
                    'supported ${caps.supported} · enabled ${caps.enabled} · '
                    'push-to-start ${caps.allowsPushStart}',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text('Run the 4-stage delivery'),
              subtitle: const Text(
                'Lock the screen, or pull down the Dynamic Island, and watch it '
                'advance every 5 seconds.',
              ),
              trailing: _running
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              onTap: _running || !ok
                  ? null
                  : () async {
                      setState(() => _running = true);
                      await liveActivity.runLocalSequence();
                      if (mounted) setState(() => _running = false);
                    },
            ),
          ),

          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Start'),
                  subtitle: Text(
                    liveActivity.running
                        ? 'Running · ${LiveActivityService.stages[liveActivity.stage]}'
                        : 'Not running',
                  ),
                  trailing: const Icon(Icons.play_circle_outline),
                  onTap: ok ? () => _do(liveActivity.start) : null,
                ),
                for (var i = 1; i < LiveActivityService.stages.length; i++)
                  ListTile(
                    dense: true,
                    title: Text('Advance to “${LiveActivityService.stages[i]}”'),
                    trailing: const Icon(Icons.skip_next),
                    onTap: ok ? () => _do(() => liveActivity.update(i)) : null,
                  ),
                ListTile(
                  title: const Text('End'),
                  trailing: const Icon(Icons.stop_circle_outlined),
                  onTap: ok ? () => _do(liveActivity.end) : null,
                ),
                ListTile(
                  dense: true,
                  title: const Text('End every activity'),
                  subtitle: const Text('Clears ones stranded by a hot restart'),
                  trailing: const Icon(Icons.cleaning_services_outlined),
                  onTap: ok ? () => _do(liveActivity.endAll) : null,
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Three different tokens', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  _TokenRow(
                    label: 'FCM registration',
                    scope: 'whole app · stable',
                    value: push.token,
                  ),
                  _TokenRow(
                    label: 'Live Activity push',
                    scope: 'this activity · dies when it ends',
                    value: liveActivity.pushToken,
                  ),
                  _TokenRow(
                    label: 'Push-to-start',
                    scope: 'the activity type · iOS 17.2+',
                    value: liveActivity.pushToStartToken,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Platform.isIOS
                        ? 'What the simulator cannot show you'
                        : 'iOS only',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Everything on this screen is driven locally, from inside '
                    'the app. That half works on the simulator, Dynamic Island '
                    'included.\n\n'
                    'Updating an activity over push does not. apsd logs show '
                    'the message arriving and the activity never changes, and '
                    'dropping in a .apns file will not start one either. On the '
                    'simulator there is no way to tell that apart from a bug in '
                    'your own code — use a physical iPhone for the push half.\n\n'
                    'Note also what is NOT in ContentState: the fields drawn on '
                    'screen travel through the shared App Group instead, so the '
                    'widget process can read what the app wrote.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TokenRow extends StatelessWidget {
  const _TokenRow({required this.label, required this.scope, required this.value});

  final String label;
  final String scope;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                v == null ? Icons.remove_circle_outline : Icons.check_circle_outline,
                size: 16,
                color: v == null ? theme.disabledColor : theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(label, style: theme.textTheme.labelLarge),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: Text(
              '$scope\n${v == null ? '—' : '…${v.substring(v.length - 16)}'}',
              style: theme.textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}
