import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../main.dart';

class PushScreen extends StatefulWidget {
  const PushScreen({super.key});

  @override
  State<PushScreen> createState() => _PushScreenState();
}

class _PushScreenState extends State<PushScreen> {
  @override
  Widget build(BuildContext context) {
    final token = push.token;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Push (FCM)')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Backend', style: theme.textTheme.labelMedium),
                  Text(push.backendLabel, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Text('Device ID', style: theme.textTheme.labelMedium),
                  Text(push.deviceId, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Text('FCM token', style: theme.textTheme.labelMedium),
                  Text(
                    token == null
                        ? 'none — on an emulator this usually means a system '
                              'image without Play Services'
                        : '…${token.substring(token.length - 24)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy token'),
                        onPressed: token == null
                            ? null
                            : () async {
                                await Clipboard.setData(
                                  ClipboardData(text: token),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Token copied'),
                                    ),
                                  );
                                }
                              },
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.cloud_upload, size: 18),
                        label: const Text('Re-register'),
                        onPressed: () async {
                          await push.register();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),
          Text('  Ask the server to push', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),

          _PushDemo(
            title: 'Notification message',
            subtitle: 'The OS draws it. The app is never consulted, so it '
                'appears even if the process is dead — but you cannot control '
                'how it looks.',
            onTap: () async {
              await push.requestPush('/api/push/notification');
              setState(() {});
            },
          ),
          _PushDemo(
            title: 'Data-only message',
            subtitle: 'Nothing is displayed until the app draws it itself. Full '
                'control over the UI, but an OEM can kill the process first and '
                'then nothing appears at all.',
            onTap: () async {
              await push.requestPush('/api/push/data');
              setState(() {});
            },
          ),
          _PushDemo(
            title: 'Topic broadcast',
            subtitle: 'Goes to every device subscribed to demo-all, not to a '
                'specific token.',
            onTap: () async {
              await push.requestPush('/api/push/topic', extra: {'topic': 'demo-all'});
              setState(() {});
            },
          ),

          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              title: const Text('Subscribe to topic demo-all'),
              subtitle: const Text('Required before topic broadcasts arrive'),
              value: push.subscribedToTopic,
              onChanged: (_) async {
                await push.toggleTopic();
                setState(() {});
              },
            ),
          ),

          const SizedBox(height: 16),
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Try this', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Fire each type three times: with the app open, with it in '
                    'the background, and after swiping it away.\n\n'
                    'The notification message survives all three. The data-only '
                    'message stops appearing once the process is gone — which is '
                    'the entire reason production apps send both.\n\n'
                    'Every event lands in the Event log with its raw payload.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.receipt_long),
        label: const Text('Log'),
        onPressed: () => context.push('/log'),
      ),
    );
  }
}

class _PushDemo extends StatelessWidget {
  const _PushDemo({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 6),
    child: ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.send),
      onTap: onTap,
    ),
  );
}
