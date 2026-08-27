import 'package:flutter/material.dart';

import '../main.dart';

class LiveUpdateScreen extends StatefulWidget {
  const LiveUpdateScreen({super.key});

  @override
  State<LiveUpdateScreen> createState() => _LiveUpdateScreenState();
}

class _LiveUpdateScreenState extends State<LiveUpdateScreen> {
  bool _running = false;

  @override
  void initState() {
    super.initState();
    liveUpdate.refreshCapabilities().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caps = liveUpdate.capabilities;

    return Scaffold(
      appBar: AppBar(title: const Text('Live Updates (Android)')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: caps.isQpr1
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        caps.isQpr1 ? Icons.check_circle : Icons.info_outline,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text('This device', style: theme.textTheme.titleSmall),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(caps.summary, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Text(
                    'SDK_INT ${caps.sdkInt} · SDK_INT_FULL ${caps.sdkIntFull} · '
                    'canPostPromoted ${caps.canPostPromoted}',
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
                'Order received → preparing → picked up → on the way, then '
                'ends. Watch the status bar, not just the shade.',
              ),
              trailing: _running
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              onTap: _running
                  ? null
                  : () async {
                      setState(() => _running = true);
                      await liveUpdate.runLocalSequence();
                      if (mounted) setState(() => _running = false);
                    },
            ),
          ),

          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Start'),
                  trailing: const Icon(Icons.play_circle_outline),
                  onTap: () => liveUpdate.start(),
                ),
                for (var i = 1; i < 4; i++)
                  ListTile(
                    dense: true,
                    title: Text('Advance to stage ${i + 1}'),
                    trailing: const Icon(Icons.skip_next),
                    onTap: () => liveUpdate.update(
                      step: i,
                      eta: ['25 min', '18 min', '12 min', '4 min'][i],
                    ),
                  ),
                ListTile(
                  title: const Text('End'),
                  trailing: const Icon(Icons.stop_circle_outlined),
                  onTap: () => liveUpdate.end(),
                ),
              ],
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
                  Text('What disqualifies promotion', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Any one of these silently drops it back to an ordinary '
                    'notification, with nothing logged to say why:\n\n'
                    '• not ProgressStyle (or BigText / Call / Metric)\n'
                    '• setRequestPromotedOngoing not called\n'
                    '• setOngoing(false)\n'
                    '• no content title\n'
                    '• custom RemoteViews\n'
                    '• used as a group summary\n'
                    '• setColorized(true)\n'
                    '• channel importance MIN\n\n'
                    'Also: if the user swipes a Live Update away, do not post it '
                    'straight back. That is the one behaviour guaranteed to make '
                    'people disable notifications entirely.',
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
