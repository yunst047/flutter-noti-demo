# flutter-noti-demo

A Flutter demo app that exercises **every kind of notification** — from a plain local
notification through to iOS Live Activities and Android Live Updates — driven by a
single Go backend so you can see exactly how each payload differs.

> **This is a learning/demo project.** Every key, ID, and URL in this repo is a
> placeholder. No real credentials are committed, and none should be.

## What it covers

| Area | Includes |
|---|---|
| Local notifications | scheduled, repeating, BigText/BigPicture/Inbox/Messaging, progress, actions, inline reply, grouping, channels, custom sound, full-screen intent |
| Push (FCM) | notification vs data-only vs silent, topics, all three app states (foreground / background / terminated) |
| Advanced push | rich media, deep links, silent-push-then-fetch |
| Android Live Updates | `Notification.ProgressStyle` promoted ongoing notification (API 36.1+) |
| iOS Live Activity | Lock screen + Dynamic Island, updated over push |

The most useful artifact here is [`docs/PAYLOADS.md`](docs/PAYLOADS.md) — the real
payload for every notification type, side by side.

## Repo layout

This is the **app half**. The Go backend that sends the pushes lives in a separate
private repo; this app only ever talks to it over HTTPS.

```
lib/
  services/     local noti, push, live activity, live update, permissions
  screens/      one screen per notification category
docs/           setup checklist, testing matrix, payload reference, decisions
```

## Running it

The backend URL and shared key are injected at build time — never hardcoded.

```bash
cp env.example.json env.local.json     # then edit it; env.local.json is gitignored
flutter run --dart-define-from-file=env.local.json
```

Against a locally-running backend on a USB-connected Android device:

```bash
adb reverse tcp:8080 tcp:8080          # tunnels over the cable; re-run after reconnect
```

## Before it will build

You must supply your own Firebase config — these files are gitignored by design:

- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `lib/firebase_options.dart` (generate with `flutterfire configure`)

Full step-by-step in [`docs/SETUP.md`](docs/SETUP.md).

## Platform support status

| | Status |
|---|---|
| Android | Verified on a Galaxy S21 (Android 15 / API 35) |
| Android Live Updates | Requires API 36.1+ — emulator only, see `docs/TESTING.md` |
| iOS | Code present, **not yet verified on device** |

`docs/TESTING.md` records exactly what can and cannot be tested on an emulator or
simulator — worth reading before debugging anything.
