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

### Backend URL is injected, never hardcoded

`--dart-define-from-file=env.local.json`, with `env.example.json` committed as the
template. A public repo should not contain a live endpoint, and the URL changes between
local development and the deployed Function URL.

### `firebase_options.dart` is gitignored

It embeds project identifiers and API keys. These are client-side values that ship inside
the app binary anyway and are not secrets in the strict sense, but a public repo should
not advertise them, and the original spec's rule was to commit no Google config files.
`firebase_options.dart.example` is committed instead.

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
| All iOS code | **Written, never built or run.** No Mac available. Do not mark verified on reasoning alone. |
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
