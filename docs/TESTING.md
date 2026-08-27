# Testing matrix

**Read this before debugging anything.** Several parts of this demo cannot work on an
emulator or simulator, and hours disappear into chasing a bug that is really a platform
limitation. Check the relevant row first.

## Hardware in use

| | |
|---|---|
| Galaxy S21 (`SM-G991B`) | Android 15 / **API 35**, One UI 7.0, Play Services 26.30.32 |
| Emulator | needed for Phase 4 only — see below |
| Mac + iPhone | required for all iOS work |

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
| 5 Live Activity | — | — | iOS only |
| 6 in-app / badge / log | ✅ | ⚠️ badge depends on launcher | |

---

## iOS

**Currently unverified.** Everything below is written but has never been built or run.

Without a Mac this is more than a device problem: Xcode is macOS-only, so the iOS app
cannot be built at all, the Simulator cannot run, and the Widget Extension and
Notification Service Extension targets cannot be created.

When the Mac is available, the simulator still has hard limits:

| | Simulator |
|---|---|
| Local notifications | ✅ fully |
| Fake push via `xcrun simctl push` | ✅ — no APNs, no token, no backend; good for UI and deep-link routing |
| Real push through APNs | ✅ only on Apple Silicon/T2, macOS 13+, simulator iOS 16+, **sandbox only** |
| Live Activity — local start/update | ✅ Dynamic Island renders on iPhone 14 Pro and later |
| Live Activity — **update via push** | ❌ **unreliable; use a physical iPhone** |

That last row matters: `apsd` logs show the message arriving but the activity does not
update, and dragging a `.apns` file in does not start one. Debugging Phase 5 push on the
simulator means being unable to tell a code bug from a simulator limitation. Use the
physical iPhone.

If you hit `BadDeviceToken`, check the hex conversion of the token before blaming the
simulator.

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
