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

<p align="center">
  <img src="docs/screenshots/ios-lockscreen-final.png" width="300" alt="iOS Live Activity on the Lock Screen" />
</p>
<p align="center">
  <img src="docs/screenshots/ios-dynamic-island-stage2.png" width="620" alt="The same activity in the Dynamic Island" />
</p>

More, and what each one is evidence of, in
[`docs/screenshots/`](docs/screenshots/README.md).

## Repo layout

This is the **app half**. The Go backend that sends the pushes lives in a separate
private repo; this app only ever talks to it over HTTPS.

```
lib/
  services/     local noti, push, live activity, live update, permissions
  screens/      one screen per notification category
docs/           setup checklist, testing matrix, payload reference, decisions
  screenshots/  evidence for every "verified" claim about iOS
  LIVE-ACTIVITY-API.md   what the backend still needs for push-driven Live Activities
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
- `ios/Runner/GoogleService-Info.plist`, then `ruby tool/link_google_services.rb` to put
  it in the Runner target — on disk is not enough, and the failure is silent

Full step-by-step in [`docs/SETUP.md`](docs/SETUP.md); how the APNs → FCM chain fits
together, and how to test each link separately, is in §D.4.

## Platform support status

| | Status |
|---|---|
| Android | Verified on a Galaxy S21 (Android 15 / API 35) |
| Android Live Updates | Requires API 36.1+ — emulator only, see `docs/TESTING.md` |
| iOS app + Live Activity | Verified on an iPhone 17 Pro simulator (iOS 26.5) — Lock Screen and Dynamic Island, [screenshots](docs/screenshots/README.md) |
| iOS push | Alert-type verified against the live backend; data-only and silent **cannot** be tested on a simulator, see `docs/TESTING.md` |
| Live Activity over push | Needs a physical iPhone; the simulator cannot do it |

`docs/TESTING.md` records exactly what can and cannot be tested on an emulator or
simulator — worth reading before debugging anything.
