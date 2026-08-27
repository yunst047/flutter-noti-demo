# Testing matrix

**Read this before debugging anything.** Several parts of this demo cannot work on an
emulator or simulator, and hours disappear into chasing a bug that is really a platform
limitation. Check the relevant row first.

## Hardware in use

| | |
|---|---|
| Galaxy S21 (`SM-G991B`) | Android 15 / **API 35**, One UI 7.0, Play Services 26.30.32 |
| Emulator | needed for Phase 4 only — see below |
| Mac | ✅ available. Xcode 26.6, iPhone 17 Pro simulator on iOS 26.5 |
| Physical iPhone | still required for the push half of Phase 5, and to sign off Phase 3 |

---

## The S21 cannot test Phase 4, and never will

Live Updates need **API 36+** for `Notification.ProgressStyle`, and actual *promotion*
to a Live Update needs **API 36.1** (Android 16 QPR1). The S21 is on API 35.

This is not a "wait for the OTA" situation. The S21 shipped with Android 11 and
Samsung's four-OS-upgrade policy ends at Android 15, so it will most likely never receive
Android 16. Samsung's Now Bar needs One UI 8 for the same reason.

On the S21, Phase 4 takes the fallback path — a foreground service with an ordinary
ongoing notification. **That is the correct behaviour, not a bug.** Verify the fallback
here, and verify promotion on the emulator.

```bash
sdkmanager "system-images;android-36.1;google_apis_playstore;x86_64"
avdmanager create avd -n noti36 -k "system-images;android-36.1;google_apis_playstore;x86_64"
```

Use `google_apis_playstore`, **not** `default` or `aosp_atd`. An image without Play
Services returns `null` from `getToken()` forever — the single most common reason people
conclude "FCM is broken".

Cold-boot an emulator that has sat unused. Clock skew breaks Play Services auth and FCM
registration fails with errors that point nowhere near the real cause.

---

## What the S21 is uniquely good for

Things no emulator reproduces:

- **Samsung/OEM background process killing.** The main reason data-only messages get
  dropped in the real world.
- **Doze on real silicon.** Simulate with
  `adb shell dumpsys deviceidle force-idle`.
- **Badge counts on the One UI launcher** — behaviour varies per launcher, so record what
  this one actually does.
- **Delivery while the app is force-stopped**, which is where data-only messages fail and
  notification messages still arrive.

---

## Per-phase matrix

| Phase | S21 | Emulator | Notes |
|---|---|---|---|
| 0 permissions | ✅ | ✅ | |
| 1 local notifications | ✅ | ✅ | no backend needed |
| 2 push basic | ✅ | ✅ (Play Services image) | |
| 3 rich / silent / deeplink | ✅ Android half | ⚠️ | force-stop behaviour needs the real device |
| 4 Live Updates | ❌ fallback only | ✅ API 36.1 | see above |
| 5 Live Activity | — | — | iOS only — see below |
| 6 in-app / badge / log | ✅ | ⚠️ badge depends on launcher | |

---

## iOS

**Builds and runs.** Verified on an iPhone 17 Pro simulator, iOS 26.5, Xcode 26.6,
Flutter 3.47.1. The project uses **Swift Package Manager**, not CocoaPods — there is no
`Podfile` and none is needed.

### What has actually been seen working

Screenshots of every row marked ✅ below are in
[`docs/screenshots/`](screenshots/README.md) — this project's rule is not to call iOS
verified without them.

| | Status |
|---|---|
| App builds and launches on the simulator | ✅ |
| `DeliveryWidget.appex` embedded, bundle ID `com.f0h.flt-noti-demo.DeliveryWidget` | ✅ |
| ActivityKit capability probe (`supported`/`enabled`/`allowsPushStart`) | ✅ all true |
| Live Activity **start**, **update ×3**, **end** driven locally | ✅ |
| Lock Screen card — title, stage, 4-segment bar, ETA, rider | ✅ |
| Dynamic Island compact leading + trailing, updating per stage | ✅ |
| Live Activity push token + push-to-start token issued | ✅ issued; the backend answers **404** on `/api/live-activity/token` |
| FCM token acquired and registered with the backend | ✅ `ios-…` (the simulator install) |
| Alert-type push, all four kinds | ✅ — see the table below |
| Data-only / silent / `content-available` push | ❌ **impossible on the simulator** — see below |

### iOS push — run against the live backend, 2026-08-28

Firebase and APNs are wired (`docs/SETUP.md` §D). The simulator got a real FCM token —
possible because this is an Apple Silicon Mac — registered it with the backend, and every
endpoint below was fired at it once.

**The backend has since been torn down (`terraform destroy`), so this table is the
record.** `/healthz` answered `{"fcmConfigured":true,"ok":true,"store":"dynamodb:noti-demo-tokens"}`
and `POST /api/tokens` returned 200 on launch.

| Endpoint | FCM | Reached the app? |
|---|---|---|
| `/api/push/notification` | `sent:1` | ✅ banner + `onMessage` |
| `/api/push/data` | `sent:1` | ❌ **simulator drops it** — see below |
| `/api/push/silent` | `sent:1` | ❌ same |
| `/api/push/rich` | `sent:1` | ✅ delivered — **without the image**, no NSE target exists |
| `/api/push/actions` | `sent:1` | ✅ → `[local] actions - id=8`, rebuilt locally with buttons |
| `/api/push/deeplink` | `sent:1` | ✅ delivered; routing happens on *tap*, so foreground only logs |
| `/api/push/topic` | `sent:1` | ✅ — **but only after subscribing** |
| `/api/simulate/delivery` | `202` in 0.2 s | ⚠️ all four steps reached the device, 20.3 s apart, then dropped |
| `/api/live-activity/token` | — | ❌ **404** — the Phase 5 backend endpoints were never written |

![Event log](screenshots/ios-push-event-log.png)

#### Data-only and silent push cannot work on the simulator. At all.

Not a bug in the app, the backend, or FCM — the pushes arrive at the device and iOS
refuses to hand them over. From the simulator's own log:

```
SpringBoard [com.f0h.flt-noti-demo] Received remote notification request
  [ waking: 1, hasAlertContent: 0, hasContentAvailable: 1, pushType: Background]
SpringBoard [com.f0h.flt-noti-demo] Content-available push notifications are only
  supported on-device for iOS, watchOS, and tvOS
```

`xcrun simctl push` with the same payload is dropped identically, which is how this was
isolated. **Anything `content-available` needs a physical iPhone**: `/api/push/data`,
`/api/push/silent`, and every `delivery_step` in the finale.

Check it yourself with:

```bash
xcrun simctl spawn booted log show --last 5m --style compact \
  --predicate 'eventMessage CONTAINS[c] "flt-noti-demo"' | grep -i content-available
```

#### `/api/simulate/delivery` works — the backend half is proven

Worth stating precisely, because `202` followed by a silent nothing looks exactly like the
async worker having died (its `maximum_retry_attempts = 0`, see `DECISIONS.md`). It did
not. Four `type = "delivery_step"` pushes arrived at 01:54:13, 01:54:33, 01:54:54 and
01:55:14 — 20.3 s apart — and every one was dropped by the rule above. Lambda → FCM →
APNs → device is sound end to end; only the last hop into the app is blocked, and only
here.

On a real iPhone these still would not drive the Live Activity: `delivery_step` is
handled natively in `DeliveryMessagingService.kt`, which is **Android-only**, and
`push_service.dart` merely logs it on iOS.

#### The topic is not subscribed at startup

`push.init()` never calls `subscribeToTopic` — the toggle on the Push screen does, and
`subscribedToTopic` starts `false`. The first `/api/push/topic` send therefore reached
nothing, and looked like a broken endpoint. It is not: subscribe first, then it arrives.

### Hard limits that remain

| | Simulator |
|---|---|
| Local notifications | ✅ fully |
| Fake push via `xcrun simctl push` | ✅ for **alert** payloads only; a `content-available` payload is dropped |
| Real push through APNs | ✅ verified — Apple Silicon, macOS 13+, simulator iOS 16+, **sandbox only** |
| Data-only / silent / `content-available` | ❌ **never delivered**, from any source |
| Live Activity — local start/update | ✅ verified, Dynamic Island included |
| Live Activity — **update via push** | ❌ **unreliable; use a physical iPhone** |

That last row matters: `apsd` logs show the message arriving but the activity does not
update, and dragging a `.apns` file in does not start one. Debugging Phase 5 push on the
simulator means being unable to tell a code bug from a simulator limitation. Use the
physical iPhone.

If you hit `BadDeviceToken`, check the hex conversion of the token before blaming the
simulator.

### Two things about the simulator worth knowing

**The first activity triggers a permission prompt.** iOS draws
*"Allow Live Activities from Notidemo?"* underneath the first card. The activity is
already on screen at that point; the prompt governs later ones.

**Driving the UI without tapping.** The demo can be exercised from the shell, which is
how the runs above were verified. `flutter run` prints a Dart VM Service URI; a
JSON-RPC `evaluate` against the root library reaches the top-level objects in
`main.dart` directly:

```
evaluate(isolateId, rootLibId, "liveActivity.runLocalSequence()")
evaluate(isolateId, rootLibId, "_router.go('/activity')")
```

Then `xcrun simctl io booted screenshot out.png` to see the result. Note the VM Service
speaks WebSocket only — an HTTP POST to the same URI returns `method not allowed`. To
reach the Lock Screen, ⌘L in Simulator; `simctl` has no lock command.

---

## Running against a local backend

The backend runs on your machine; the phone reaches it over the USB cable:

```bash
adb reverse tcp:8080 tcp:8080     # re-run after every reconnect
flutter run --dart-define-from-file=env.local.json
```

with `API_BASE_URL=http://localhost:8080`. On an emulator use `http://10.0.2.2:8080`
instead — that is the host-machine alias.

Both are plain HTTP to localhost, which Android permits with no cleartext exception. Only
the deployed Function URL needs TLS.

---

## Build environment notes

This machine has ~15 GB RAM and typically under 1 GB free with an IDE open. Two
consequences, both already handled in the committed config:

- `android/gradle.properties` sets `-Xmx1536m`. The Flutter template ships `-Xmx8G`,
  which the JVM cannot even reserve here — the build dies with *"insufficient memory for
  the Java Runtime Environment to continue"* before compiling anything.
- Go builds of the backend need `go build -p 1`; full parallelism exhausts the pagefile
  while compiling the AWS SDK.

If a build fails on memory, language servers are the usual culprits — `terraform-ls` and
`gopls` reserve far more *committed* memory than their working sets suggest. Killing them
freed ~15 GB of commit charge in one instance. VS Code restarts them on demand.

`android/app/build.gradle.kts` pins `ndkVersion` to the installed NDK rather than the one
Flutter defaults to. AGP otherwise tries to auto-download it via `sdkmanager.bat`, which
crashes with `0xC0000409` in this SDK release.
