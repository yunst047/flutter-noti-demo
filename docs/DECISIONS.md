# Decisions

Every point where a choice was made on your behalf, and why. Reverse any of these freely
— the reasoning is here so you can disagree with it.

---

## Architecture

### Backend runs on AWS Lambda, not EC2

**The deciding factor is TLS, not cost.** The phone calls this API directly, and both iOS
ATS and Android's cleartext policy require a publicly-trusted certificate.

A Lambda Function URL provides `https://<id>.lambda-url.<region>.on.aws` with a valid
AWS-managed cert for free. EC2 would have meant either buying a domain and running Caddy
for Let's Encrypt (~$12/yr plus ~$6/mo for the box) or an ALB (~$17/mo). Without a
trusted cert we would be adding ATS exceptions to the app — insecure workarounds inside a
demo whose whole purpose is showing correct notification wiring.

Two consequences fall out:

- Lambda outside a VPC has internet egress by default, so reaching `fcm.googleapis.com`
  needs **no NAT Gateway** (~$32/mo avoided).
- Idle cost is effectively zero.

**EC2 would have been the better choice if** we needed long-lived WebSocket/SSE
connections (Lambda cannot hold those), or if "SSH in and tail logs" were itself a goal.

### Device tokens live in DynamoDB, not in memory

Forced by the choice above. Lambda execution environments do not share memory and are
torn down after idle, so a token registered by one invocation is invisible to the next.

Incidentally an improvement: tokens now survive restarts, so you can register on Monday
and push on Friday without reopening the app. An in-memory implementation is kept behind
the same interface so `go run ./cmd/local` needs no AWS credentials at all.

### All FCM traffic uses raw HTTP v1, not the Firebase Admin SDK

**This deviates from the original plan**, which used the Admin SDK for ordinary pushes and
raw HTTP v1 only for Live Activities (where the SDK has no `live_activity_token` field).

`docs/PAYLOADS.md` is the main deliverable of this demo. With the Admin SDK, the actual
request body is assembled inside the library, so anything we logged would be a
reconstruction of the payload rather than the payload. Going raw everywhere means the
JSON in the logs is byte-for-byte what went on the wire. One auth path and one code path
is a secondary benefit.

**Cost:** no built-in error classification for dead tokens (`UNREGISTERED` and friends
must be parsed from the error body), and no batch send. Both are irrelevant at demo
scale. Revisit if this ever fans out to many devices.

### `/api/simulate/delivery` returns 202 and hands off

The sequence takes ~80 seconds. Holding the HTTP connection open for that long risks
client timeouts and, on Lambda, bills the entire wait. So the API function
async-invokes a separate worker function and returns immediately.

The worker's async config sets `maximum_retry_attempts = 0`. Lambda retries failed async
invocations **twice** by default, which would replay the delivery from step 1 and show
the user the whole sequence two or three times.

### Function URL auth is a shared header, not IAM

`authType = NONE` plus an `X-Demo-Key` header checked in middleware.

`AWS_IAM` would require SigV4 signing in the Flutter app, meaning AWS credentials shipped
on-device — worse than the problem it solves. **This is demo-grade auth and should not be
copied into production.** Without the header check the endpoint is world-callable and
anyone could push to every registered device.

---

## Repos

### Two repos, not one

The app is public on GitHub; the backend is private on GitLab. The public repo must never
carry Terraform, IAM policies, the AWS account ID, or the path to the FCM service account.

`docs/` lives in the public app repo because it is the demo's real deliverable and
contains no secrets — but AWS account IDs, ARNs, Function URLs and device tokens are
redacted there. The architecture plan containing the real account ID lives only in the
private repo.

### Commits use a personal email, set per-repo

`david8.kbr@gmail.com`, configured with repo-local `git config`, not globally. The global
identity remains the work address. Rewriting history later to strip a work email out of a
public repo is painful, so this was set before the first commit.

### Infra is applied locally; CI only deploys code

Your call. Infra changes are rare and risky, so they stay manual and reviewed; code
deploys are frequent and mechanical, so they are automated. `.gitlab-ci.yml` never runs
Terraform.

The CI user should be a dedicated `noti-demo-ci` IAM user limited to
`lambda:UpdateFunctionCode` on the two function ARNs — **not** `demo_admin` keys.

---

## App

### The two platforms deliberately use different IDs

| Platform | ID |
|---|---|
| Android `applicationId` | `com.f0h.fltnotidemo` |
| iOS bundle ID | `com.f0h.flt-noti-demo` |
| iOS widget extension | `com.f0h.flt-noti-demo.DeliveryWidget` |

Not an oversight. Android `applicationId` segments accept only letters, digits and
underscores — hyphens are rejected outright. iOS bundle IDs accept hyphens but **not**
underscores. There is therefore no hyphenated name legal on both, and the requested
`com.f0h.flt-noti-demo` could only be honoured on iOS.

The widget extension still nests under the iOS bundle ID, which is what matters: Live
Activities silently fail if the extension's ID is not a child of the app's.

**Consequence: Firebase needs two separate app registrations**, one per ID. Registering
one and pointing both platforms at it produces `SENDER_ID_MISMATCH` from FCM — an error
that reads like a credentials problem rather than a naming one.

A single shared ID (`com.f0h.fltnotidemo` everywhere) would have avoided the split.

### The widget extension target is added by script, not by the Xcode wizard

`File → New → Target → Widget Extension` is GUI-only, and this project is otherwise
driven from the shell. `tool/add_widget_target.rb` does the same edits through the
`xcodeproj` gem that CocoaPods already installs: it creates the `DeliveryWidget` target,
its build settings, the embed-in-app copy phase and the `Runner` → widget dependency.

The result is a normal `.xcodeproj` — Xcode neither knows nor cares how the target was
written. The script is idempotent: it deletes any existing `DeliveryWidget` target first,
so re-running it after an edit does not produce a second one.

**Consequence:** the project uses **Swift Package Manager**, not CocoaPods. There is no
`Podfile`. The widget target links nothing beyond ActivityKit, WidgetKit and SwiftUI, so
it needs no Flutter plumbing of its own.

### The extension's version comes from an xcconfig, not from build settings

An app extension must carry `CFBundleVersion` and `CFBundleShortVersionString`, and they
must match the app embedding it. The obvious spelling — `$(FLUTTER_BUILD_NAME)` in the
extension's `Info.plist`, copied from Runner's — expands to **empty**, because those
variables are defined in `Flutter/Generated.xcconfig`, which only the Runner target
includes.

The failure is not a build error. The `.appex` builds cleanly and then install fails
with:

```
Failed to create app extension placeholder for .../DeliveryWidget.appex
Invalid placeholder attributes.
```

`ios/DeliveryWidget/DeliveryWidget.xcconfig` optionally includes Flutter's generated
xcconfig and maps the two values through, so the extension's version tracks
`pubspec.yaml` automatically:

```
#include? "../Flutter/Generated.xcconfig"
MARKETING_VERSION=$(FLUTTER_BUILD_NAME:default=1.0.0)
CURRENT_PROJECT_VERSION=$(FLUTTER_BUILD_NUMBER:default=1)
```

Hardcoding `1.0` would have worked today and drifted the first time the app version was
bumped.

### The widget deploys to iOS 16.2, the app to 15.0

An embedded extension may target a *higher* version than its host, and Live Activities do
not exist below 16.1 — so holding the widget back to 15.0 would only mean scattering
`@available` guards through views that cannot run there anyway. 16.2 rather than 16.1
because the plugin uses `ActivityContent` with a stale date, which is 16.2.

The app keeps 15.0: nothing else in the demo needs a newer floor, and raising it would
drop devices from the parts that do work.

### Live Activity fields travel through the App Group, not through `ContentState`

This looks wrong on first reading and is worth knowing before editing the widget.

ActivityKit requires the *same* `ActivityAttributes` type in the app and in the widget
process. A Flutter plugin cannot know the fields of an app it has never seen, so
`live_activities` ships a fixed `LiveActivitiesAppAttributes` whose `ContentState` carries
only the App Group id. Everything drawn on screen — order id, stage, ETA, rider — is
written by the app into that group's `UserDefaults` under keys prefixed with the
activity's UUID, and read back by the extension.

Two consequences:

- **The struct's name is load-bearing.** Rename `LiveActivitiesAppAttributes` in the
  widget and the activity is created, returns an id, reports itself active, and never
  appears. Nothing is logged.
- The App Group is not optional plumbing. It is the data path.

Writing a bespoke ActivityKit bridge instead would have allowed a typed `ContentState`
and made the demo's payload story cleaner.

**This is not merely cleaner — it is required for server-driven updates.** A Live Activity
push does not wake the app, so no process exists to write the App Group keys, and
`ContentState.init(from:)` discards every field it does not recognise. A push-driven
update therefore re-renders the widget from *unchanged* storage and nothing on screen
moves. The endpoints in `LIVE-ACTIVITY-API.md` are useless until the drawn fields live in
`ContentState`, which means dropping `live_activities`. Local updates from inside the app
are unaffected, which is why Phase 5 demos correctly today.

### Backend URL is injected, never hardcoded

`--dart-define-from-file=env.local.json`, with `env.example.json` committed as the
template. A public repo should not contain a live endpoint, and the URL changes between
local development and the deployed Function URL.

### `firebase_options.dart` is gitignored — and unused

It embeds project identifiers and API keys. These are client-side values that ship inside
the app binary anyway and are not secrets in the strict sense, but a public repo should
not advertise them, and the original spec's rule was to commit no Google config files.

**Correction.** An earlier version of this note said `firebase_options.dart.example` is
committed instead. It is not, and it was never needed: `Firebase.initializeApp()` is
called with **no `options:` argument**, so nothing in `lib/` imports `firebase_options.dart`
at all. Each platform reads its own native config instead —
`ios/Runner/GoogleService-Info.plist` and `android/app/google-services.json`.

That makes the plist's **target membership** the thing that decides whether iOS push works
(`tool/link_google_services.rb`), and it means `flutterfire configure` is a convenience
here rather than a requirement.

Passing `options: DefaultFirebaseOptions.currentPlatform` would move that configuration
into Dart and remove the target-membership trap entirely — a reasonable change, but it
would also put the project id and API key into a committed source file, which is what the
rule above exists to prevent.

---

## Build environment

These are workarounds for this specific machine, not general good practice.

### Gradle heap lowered to 1536m

The Flutter template ships `-Xmx8G -XX:MaxMetaspaceSize=4G`. This machine has ~15 GB
total and typically under 1 GB free, so the JVM could not even reserve that and the build
failed before compiling anything.

### `ndkVersion` pinned to the installed NDK

Flutter defaults to NDK `28.2.13676358`, which is not installed. AGP then tries to fetch
it through `sdkmanager.bat`, which crashes with `0xC0000409` in this SDK release. Nothing
in this project or its plugins ships native C/C++ code, so the revision is irrelevant and
pinning avoids a ~2.5 GB download. **Revisit if a plugin with native code is added.**

### Go backend builds with `-p 1`

Full-parallelism compilation of the AWS SDK exhausts the pagefile on this machine.

---

## Deferred / unverified

| Item | Status |
|---|---|
| iOS app + Live Activity | ✅ Built and run on an iPhone 17 Pro simulator (iOS 26.5). Lock Screen and Dynamic Island verified through a full 4-stage run — screenshots in [`docs/screenshots/`](screenshots/README.md), which is what "verified" means here. |
| iOS push — alert-type | ✅ Verified 2026-08-28 against the deployed backend: notification, rich, actions, deeplink, topic. Table in `TESTING.md`. |
| iOS push — data-only / silent | ⛔ **Cannot be tested on a simulator by any means.** iOS drops `content-available` before the app sees it, and says so in the log. Needs a physical iPhone. |
| iOS rich push image | ❌ Arrives without the attachment — no Notification Service Extension target exists. |
| `/api/live-activity/token` | ❌ Backend returns **404**. The Phase 5 server endpoints were never written; the app sends both tokens and nothing receives them. Requirements — including a blocker that has to be fixed in the app first — in [`docs/LIVE-ACTIVITY-API.md`](LIVE-ACTIVITY-API.md). |
| Live Activity **over push** | **Not attempted, deliberately.** The simulator cannot do it (`TESTING.md`), and the backend endpoints for it are not written. Needs a physical iPhone. |
| iOS Notification Service Extension (Phase 3 rich push) | **Not started.** No `NotiServiceExtension` target exists; `mutable-content` pushes will display without their attachment. |
| iOS signing for a real device | Not configured. No `DEVELOPMENT_TEAM` is set, and the App Group and App IDs are not registered in the portal. Simulator builds do not check any of this. |
| Terraform in `infra/` | ✅ Applied — 10 resources live. |
| Lambda Function URL | ⚠️ Returns 403; see below. The function itself works on direct invoke. |
| Phase 4 Live Updates | Cannot be verified on the S21 (API 35). Needs an API 36.1 emulator. |
| Custom notification sound on iOS | `demo_chime.wav` exists only under `android/`. iOS needs it added to the Xcode bundle. |

### Correction: Terraform was never blocked

An earlier note here claimed an Application Control policy blocked `terraform.exe`. That
was wrong. The policy blocks the **unsigned chocolatey shim** at
`chocolatey\bin\terraform.exe`; the HashiCorp-signed binary at
`chocolatey\lib\terraform\tools\terraform.exe` runs normally. Invoke that path directly.

### The Function URL 403 is an account setting, not a config error

`terraform apply` succeeds and every resource is created correctly — resource policy
grants `lambda:InvokeFunctionUrl` to `*`, `AuthType` is `NONE` — yet the URL returns
`403 AccessDeniedException`.

AWS accounts created since roughly 2024 enable account-level **Block Public Access for
Lambda** by default, which rejects `AuthType NONE` function URLs before the request
reaches the function. It cannot be changed from Terraform or the AWS CLI (aws-cli 2.36
has no such operation): **Lambda console → Account settings → Block public access**.

Confirm the function is healthy independently of the URL:

```bash
aws lambda invoke --function-name noti-demo-api --payload <base64 event> out.json
```

This account also reports `ConcurrentExecutions: 10` against a normal default of 1000 —
a new-account restriction, fine for a demo but worth knowing.

### Android sound and vibration are per-channel, not per-notification

Five separate channels exist (`demo_silent`, `demo_sound_only`, `demo_vibrate_only`,
`demo_custom_sound`, `demo_long_vibrate`) because on Android 8+ sound and vibration are
fixed when a channel is **created**. Setting `playSound: false` on an individual
notification is ignored, and recreating the channel with new settings does not reliably
take effect either — Android deliberately lets the user own how noisy an app may be.

The "Try to force silence" button in the Local notifications screen demonstrates this
failing on purpose. iOS has no channel model, so the same flag works there.
