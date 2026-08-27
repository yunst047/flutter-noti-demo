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

### Bundle ID `com.yunst047.notidemo`

Chosen so the iOS Widget Extension can nest beneath it as
`com.yunst047.notidemo.DeliveryWidget`. Live Activities silently fail if the extension's
bundle ID is not a child of the main one, and the name has no underscores so the Android
`applicationId` and the iOS bundle ID are identical.

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
| Terraform in `infra/` | **Never `fmt`'d, `validate`d or applied.** `terraform.exe` is blocked by an Application Control policy on this machine. |
| Phase 4 Live Updates | Cannot be verified on the S21 (API 35). Needs an API 36.1 emulator. |
