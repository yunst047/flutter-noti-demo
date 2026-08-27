import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../main.dart';
import '../services/local_noti_service.dart';

/// One card per notification variant, so they can be fired back to back and
/// compared directly.
class LocalNotiScreen extends StatelessWidget {
  const LocalNotiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local notifications'),
        actions: [
          IconButton(
            tooltip: 'Cancel all',
            icon: const Icon(Icons.clear_all),
            onPressed: localNoti.cancelAll,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _Group('Basics', [
            _Demo('Show now', 'Fires immediately', localNoti.showNow),
            _Demo(
              'Schedule in 10s',
              'zonedSchedule in the device timezone, exact-while-idle',
              () => localNoti.scheduleIn(const Duration(seconds: 10)),
            ),
            _Demo(
              'Repeat every minute',
              'Keeps firing until cancelled',
              localNoti.repeatEveryMinute,
            ),
            _Demo(
              'Cancel the repeating one',
              'Cancels id 3 only',
              () => localNoti.cancel(3),
            ),
          ]),

          _Group('Styles (Android)', [
            _Demo('BigText', 'Expands to the full message', localNoti.showBigText),
            _Demo('Inbox', 'A list of lines with a summary', localNoti.showInbox),
            _Demo('Messaging', 'Chat thread with per-person avatars', localNoti.showMessaging),
          ]),

          _Group('Progress', [
            _Demo(
              'Progress 0 → 100',
              'Ten updates over ten seconds, same notification ID',
              () => localNoti.runProgress(),
            ),
          ]),

          _Group('Interaction', [
            _Demo('Action buttons', 'Accept / Decline — result lands in the log', localNoti.showWithActions),
            _Demo('Inline reply', 'Type without opening the app; text appears in the log', localNoti.showInlineReply),
            _Demo('Grouping', 'Five children plus a summary', localNoti.showGroup),
          ]),

          _Group('Channels (Android)', [
            _Demo(
              'High importance',
              'Heads-up banner and sound',
              () => localNoti.showOnChannel(LocalNotiService.channelHigh, 'High'),
            ),
            _Demo(
              'Default importance',
              'Sound, no heads-up',
              () => localNoti.showOnChannel(LocalNotiService.channelDefault, 'Default'),
            ),
            _Demo(
              'Low importance',
              'Silent, tray only',
              () => localNoti.showOnChannel(LocalNotiService.channelLow, 'Low'),
            ),
          ]),

          _Group('Sound & vibration', [
            _Demo(
              'Silent',
              'High importance, no sound, no vibration',
              () => localNoti.showSoundVariant(
                LocalNotiService.channelSilent,
                'Silent',
              ),
            ),
            _Demo(
              'Sound only',
              'Default sound, vibration suppressed',
              () => localNoti.showSoundVariant(
                LocalNotiService.channelSoundOnly,
                'Sound only',
              ),
            ),
            _Demo(
              'Vibrate only',
              'Vibration, no sound',
              () => localNoti.showSoundVariant(
                LocalNotiService.channelVibrateOnly,
                'Vibrate only',
              ),
            ),
            _Demo(
              'Custom sound',
              'Plays res/raw/demo_chime.wav instead of the system sound',
              () => localNoti.showSoundVariant(
                LocalNotiService.channelCustomSound,
                'Custom sound',
              ),
            ),
            _Demo(
              'Custom vibration pattern',
              'Long SOS-like pattern — put the phone off silent to feel it',
              () => localNoti.showSoundVariant(
                LocalNotiService.channelLongVibrate,
                'Long vibration',
              ),
            ),
            _Demo(
              '⚠ Try to force silence',
              'Sets playSound:false on a channel created WITH sound. On '
                  'Android 8+ it still makes noise — the channel wins, not the '
                  'notification. iOS respects it. This is the most common '
                  '"why won\'t it go quiet" bug.',
              localNoti.showChannelOverrideAttempt,
            ),
          ]),

          _Group('Edge cases', [
            _Demo(
              'Full-screen intent',
              'Incoming-call style. Falls back to heads-up when the permission '
                  'is not granted — that is the documented behaviour, not a bug.',
              localNoti.showFullScreen,
            ),
            if (Platform.isIOS) ...[
              _Demo(
                'Interruption: passive',
                'No sound, no screen wake',
                () => localNoti.showInterruptionLevel(InterruptionLevel.passive),
              ),
              _Demo(
                'Interruption: time-sensitive',
                'Breaks through Focus modes',
                () => localNoti.showInterruptionLevel(InterruptionLevel.timeSensitive),
              ),
              _Demo(
                'Interruption: critical',
                'Needs an Apple-granted entitlement; degrades quietly without it',
                () => localNoti.showInterruptionLevel(InterruptionLevel.critical),
              ),
            ],
          ]),

          if (!Platform.isIOS)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'iOS interruption levels are hidden on Android — the platform '
                'ignores them entirely, so a button here would prove nothing.',
                style: TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title, this.children);

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      ...children,
    ],
  );
}

class _Demo extends StatelessWidget {
  const _Demo(this.title, this.subtitle, this.onTap);

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 6),
    child: ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.play_arrow),
      onTap: onTap,
    ),
  );
}
