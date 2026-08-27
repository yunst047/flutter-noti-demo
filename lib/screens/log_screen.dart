import 'package:flutter/material.dart';

import '../services/noti_log.dart';

class LogScreen extends StatelessWidget {
  const LogScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Event log'),
      actions: [
        IconButton(
          tooltip: 'Clear',
          icon: const Icon(Icons.delete_outline),
          onPressed: NotiLog.instance.clear,
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: NotiLog.instance,
      builder: (context, _) {
        final events = NotiLog.instance.events;
        if (events.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Nothing yet.\n\nFire a notification, then tap it — both the '
                'send and the tap should appear here.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.separated(
          itemCount: events.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final e = events[i];
            return ListTile(
              dense: true,
              leading: _SourceChip(e.source),
              title: Text(e.action),
              subtitle: e.detail.isEmpty ? null : Text(e.detail),
              trailing: Text(
                e.time,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            );
          },
        );
      },
    ),
  );
}

class _SourceChip extends StatelessWidget {
  const _SourceChip(this.source);

  final String source;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (source) {
      'tap' => scheme.tertiaryContainer,
      'push' => scheme.secondaryContainer,
      'permission' => scheme.surfaceContainerHighest,
      _ => scheme.primaryContainer,
    };
    return Container(
      width: 64,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        source,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}
