import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const sections = [
      _Section(
        route: '/permissions',
        icon: Icons.lock_outline,
        title: 'Permissions',
        subtitle: 'Runtime prompts, provisional auth, exact alarms',
        phase: 'Phase 0',
        ready: true,
      ),
      _Section(
        route: '/local',
        icon: Icons.notifications_active_outlined,
        title: 'Local notifications',
        subtitle: 'Styles, actions, inline reply, grouping, progress',
        phase: 'Phase 1',
        ready: true,
      ),
      _Section(
        route: '/push',
        icon: Icons.cloud_outlined,
        title: 'Push (FCM)',
        subtitle: 'Notification vs data-only vs silent, topics',
        phase: 'Phase 2',
        ready: true,
      ),
      _Section(
        route: '/live',
        icon: Icons.local_shipping_outlined,
        title: 'Live Updates (Android)',
        subtitle: 'Promoted ongoing notification via ProgressStyle',
        phase: 'Phase 4',
        ready: true,
      ),
      _Section(
        route: '/activity',
        icon: Icons.blur_circular_outlined,
        title: 'Live Activity (iOS)',
        subtitle: 'ActivityKit on the Lock Screen and Dynamic Island',
        phase: 'Phase 5',
        ready: true,
      ),
      _Section(
        route: '/log',
        icon: Icons.receipt_long_outlined,
        title: 'Event log',
        subtitle: 'Everything received, displayed, tapped',
        phase: 'Phase 6',
        ready: true,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Notification Demo')),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: sections.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) => sections[i],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.route,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.phase,
    required this.ready,
  });

  final String route;
  final IconData icon;
  final String title;
  final String subtitle;
  final String phase;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      enabled: ready,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Chip(
        label: Text(phase, style: theme.textTheme.labelSmall),
        visualDensity: VisualDensity.compact,
        side: BorderSide.none,
        backgroundColor: ready
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
      ),
      onTap: ready ? () => context.push(route) : null,
    );
  }
}
