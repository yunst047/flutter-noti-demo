# Setup checklist

Manual steps that must be done by hand in a console. Work top to bottom; each section
says what unblocks.

Console UIs change wording often. Where a label here doesn't match what you see, follow
the console's own wording — the *intent* of each step is what matters, and the values
you need to collect are listed at the end of each section.

**Nothing here is needed for Phase 0 or Phase 1.** Local notifications and permissions
work with no Firebase and no AWS. Start this when you want Phase 2 (push).

---

## A. Firebase — Android  ✅ do this now

Unblocks: Phase 2 push on the S21.

> **The two platforms use different IDs.** Android rejects hyphens in an
> `applicationId`; iOS bundle IDs allow them. So Firebase needs **two separate app
> registrations**, and mixing them up produces a `SENDER_ID_MISMATCH` from FCM.
>
> | Platform | ID |
> |---|---|
> | Android `applicationId` | **`com.f0h.fltnotidemo`** (no hyphens) |
> | iOS bundle ID | **`com.f0h.flt-noti-demo`** (hyphens) |
> | iOS widget extension | `com.f0h.flt-noti-demo.DeliveryWidget` |

- [ ] Create a project at <https://console.firebase.google.com>
- [ ] **Project settings → Your apps → Add app → Android**
- [ ] Android package name: **`com.f0h.fltnotidemo`** — must match exactly, this is
      the `applicationId` in `android/app/build.gradle.kts`. **No hyphens.**
- [ ] Download **`google-services.json`** → place at **`android/app/google-services.json`**
      (gitignored)
- [ ] Install the FlutterFire CLI and generate the options file:
      ```bash
      dart pub global activate flutterfire_cli
      flutterfire configure --project=<your-project-id>
      ```
      This writes `lib/firebase_options.dart` (also gitignored).

**Collect:** Firebase **Project ID** — the backend puts it in the FCM v1 endpoint URL.

> FCM HTTP v1 is enabled by default on new projects. The old "Cloud Messaging API
> (Legacy)" / server keys were shut off in June 2024 and are not used here at all.

---

## B. Service account for the backend  ✅ do this now

Unblocks: the backend's ability to send anything.

Do **not** use Firebase's "Generate new private key" button under Service accounts — that
key carries broad Firebase Admin rights. Create a narrowly-scoped one instead:

- [ ] <https://console.cloud.google.com> → **IAM & Admin → Service Accounts → Create**
      (same project as Firebase)
- [ ] Grant exactly one role: **Firebase Cloud Messaging API Admin**
      (`roles/firebasecloudmessaging.admin`) — this permits `cloudmessaging.messages.create`
      and nothing else that matters
- [ ] Open the account → **Keys → Add key → Create new key → JSON** → download

**Collect:** the JSON file. Keep it **outside both repos** — `C:\Users\<you>\.secrets\`
is what this project uses. It goes into AWS Secrets Manager; a local copy is only for
`FCM_CREDENTIALS_FILE` during development.

> **Never leave a downloaded key inside a repo, even briefly.** GCP names them
> `<project-id>-<hash>.json`, which matches no obvious "service-account" ignore pattern —
> a `git add -A` will happily commit one. The backend repo now denies every `.json` at
> its root by default rather than relying on name matching.

### Two things that will fail even with a valid key

Both produce 403s that look like credential problems but are not:

- [ ] **Enable the FCM API on the project.** A new project has it off, and you get
      `SERVICE_DISABLED`:
      ```bash
      gcloud services enable fcm.googleapis.com --project=<project-id>
      ```
- [ ] **Grant the right role.** Creating the service account through the Firebase console
      may leave it with `roles/firebasenotifications.admin` — the *legacy* Notifications
      role, which does **not** permit `cloudmessaging.messages.create` on the v1 API. You
      need:
      ```bash
      gcloud projects add-iam-policy-binding <project-id> \
        --member="serviceAccount:<sa>@<project-id>.iam.gserviceaccount.com" \
        --role="roles/firebasecloudmessaging.admin"
      ```
      Allow ~30–60s for IAM to propagate; until it does you keep getting
      `Permission 'cloudmessaging.messages.create' denied`.

**Verify the whole chain** without a real device — a made-up token should be rejected by
FCM itself (`INVALID_ARGUMENT`), not by auth:

```bash
curl -XPOST -H "X-Demo-Key: $KEY" $API_BASE_URL/api/push/notification \
  -d '{"deviceId":"probe","title":"t","body":"b"}'
```

---

## C. AWS  ✅ done

Unblocks: the deployed HTTPS endpoint, so the app works away from a USB cable.

> **Complete.** 14 resources are live, both Lambdas run the real code, and the endpoint
> is verified end to end — `/healthz` returns `fcmConfigured: true` and a push with an
> invalid token is rejected by FCM itself rather than failing auth.
>
> On this machine, invoke Terraform by its full path:
> `C:\ProgramData\chocolatey\lib\terraform\tools\terraform.exe`. The Application Control
> policy blocks the *unsigned chocolatey shim* in `chocolatey\bin`, not Terraform itself.

- [x] `cd infra && cp terraform.tfvars.example terraform.tfvars`, fill in
      `firebase_project_id` and an `api_key` (`openssl rand -hex 24`)
- [x] `terraform init && terraform plan && terraform apply`
- [x] Populate the secret **out of band** — Terraform creates it empty on purpose, so the
      private key never enters Terraform state:
      ```bash
      aws secretsmanager put-secret-value \
        --secret-id noti-demo/fcm-sa \
        --secret-string file://C:/Users/<you>/.secrets/noti-demo-fcm-sa.json
      ```
- [x] `terraform output api_base_url` → becomes `API_BASE_URL` in `env.local.json`

### Why this is API Gateway and not a Lambda Function URL

The design originally used a Function URL — simpler and free. It cannot work on this
account. Accounts created since roughly 2024 enable account-level **Block Public Access
for Lambda** by default, which rejects `AuthType NONE` function URLs with
`403 AccessDeniedException` *before the request reaches the function*, regardless of the
resource policy. Terraform reports success the whole time, because every resource really
is created correctly.

It cannot be disabled from Terraform or the AWS CLI (aws-cli 2.36 has no such operation),
and the `PutPublicAccessBlockConfig` REST API would not route when called directly with a
hand-signed request — AWS appears to have partially withdrawn it.

API Gateway HTTP API is not subject to the restriction, still provides a valid
AWS-managed certificate, and costs ~$1 per million requests with **no fixed monthly
charge** — unlike an ALB, nothing accrues while idle.

**For CI** (only needed once you want push-to-deploy):

- [ ] Create an IAM user `noti-demo-ci` with a single permission,
      `lambda:UpdateFunctionCode`, scoped to the two function ARNs. **Do not use
      `demo_admin`'s keys in CI.**
- [ ] Add to GitLab → Settings → CI/CD → Variables, all **masked + protected**:
      `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION=ap-southeast-1`

**For CI** (only needed once you want push-to-deploy):

- [ ] Create an IAM user `noti-demo-ci` with a single permission,
      `lambda:UpdateFunctionCode`, scoped to the two function ARNs. **Do not use
      `demo_admin`'s keys in CI.**
- [ ] Add to GitLab → Settings → CI/CD → Variables, all **masked + protected**:
      `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION=ap-southeast-1`

---

## D. Apple  ◐ partly done — the console half is still outstanding

Unblocks: anything iOS.

> **The Mac is here now.** Everything that lives in the repo — the widget extension
> target, the entitlements, the Info.plist keys, the `AppDelegate` wiring — is committed
> and builds, and the Live Activity is verified on the simulator. What is left is the
> part that can only be done by hand in Apple's and Firebase's consoles: D.1 and D.2.
>
> Until those are done, **iOS push does not work at all** — the app logs
> `[core/not-initialized]` at startup and carries on. Local notifications and the Live
> Activity are unaffected, because neither goes anywhere near Firebase.

### D.1 Apple Developer portal

- [ ] **Identifiers → App ID** for `com.f0h.flt-noti-demo` → enable **Push Notifications**
      → Save. The Widget Extension does **not** need this ticked.
- [ ] **Identifiers → App Groups** → register `group.com.f0h.flt-noti-demo`, then tick it
      on **both** App IDs (`…flt-noti-demo` and `…flt-noti-demo.DeliveryWidget`).
      Only needed for a physical device — the simulator does not check entitlements.
- [ ] **Keys → +** → name it → enable **Apple Push Notifications service (APNs)** →
      Register
- [ ] **Download the `.p8`** — available exactly once. Miss it and you must create a new
      key.

**Collect:** **Key ID** (10 chars), **Team ID**, **Bundle ID**.

Use the Auth Key (`.p8`), not the older certificate flow: one key covers every app in the
team and never expires.

**The `.p8` goes to Firebase and nowhere else.** Not into this repo, not into the backend
repo, not into Secrets Manager. Firebase is what talks to APNs; the backend only ever
talks to FCM. See the chain in D.4.

### D.2 Firebase — iOS

- [ ] Add an iOS app to the same Firebase project, bundle ID `com.f0h.flt-noti-demo`.
      **A separate registration from the Android one** — the two platforms use different
      IDs, and pointing both at one app gives `SENDER_ID_MISMATCH` on send.
- [ ] Download `GoogleService-Info.plist` → put it at `ios/Runner/GoogleService-Info.plist`
      → then:
      ```bash
      ruby tool/link_google_services.rb
      ```
      The usual instruction is *drag it into Xcode and tick target membership = Runner*.
      **The tick is the part that matters and the part people miss**: the app calls
      `Firebase.initializeApp()` with no options, so on iOS it reads this file out of the
      app *bundle*. On disk but not in the target means it is never copied, and the app
      logs `[core/not-initialized]` — which reads like a credentials problem and is not.
      The script does the same edit and refuses a plist whose `BUNDLE_ID` is wrong.

      **Do not commit the `project.pbxproj` change it makes.** The plist is gitignored,
      so a checkout that references it without containing it fails the build outright —
      `Build input file cannot be found`. The committed project deliberately does not
      reference the plist; every clone runs this script once after supplying its own.
- [ ] **Project settings → Cloud Messaging → Apple app configuration → upload the APNs
      Auth Key** with Key ID + Team ID

> This is what lets FCM reach iOS. Firebase holds the `.p8` and talks to APNs for you,
> which means **the AWS backend never needs the `.p8` at all**.

**Prove the file is actually in the bundle** — the only check that settles it:

```bash
flutter build ios --simulator --debug
ls build/ios/iphonesimulator/Runner.app/GoogleService-Info.plist
```

Then run the app and watch for the line that replaces `[push] init failed`:

```
[push] token acquired - …<last 12 chars>
```

A `null` token on iOS means APNs never issued one — check D.1 and D.3, not Firebase.

### D.3 Xcode  ✅ done — nothing to click

These are normally done through Xcode's Signing & Capabilities tab, which only writes
files. Those files are in the repo, so there is nothing to do here:

- [x] **Push Notifications** — `aps-environment` in `ios/Runner/Runner.entitlements`
- [x] **Background Modes** — `remote-notification` and `fetch` in `UIBackgroundModes`
      (`ios/Runner/Info.plist`)
- [x] `NSSupportsLiveActivities = YES` in the Runner **and** widget Info.plists, plus
      `NSSupportsLiveActivitiesFrequentUpdates` so a 4-step run is not throttled
- [x] Widget Extension `DeliveryWidget`, bundle ID **`com.f0h.flt-noti-demo.DeliveryWidget`**
      — a child of the app's ID, which is what ActivityKit requires. Anything else and
      the activity is created, reports itself active, and never appears.
- [x] App Group **`group.com.f0h.flt-noti-demo`** on both targets
- [x] The explicit `setAPNSToken` call below, in `ios/Runner/AppDelegate.swift`

The extension target was added by script (`xcodeproj` gem) rather than through
**File → New → Target**, because that wizard is GUI-only. Re-running the script replaces
the target instead of adding a second one; see `docs/DECISIONS.md`.

**Still needed for a physical device** (the simulator does not check any of it):

- [ ] Set a **Development Team** on the Runner and DeliveryWidget targets
- [ ] Register the App Group and both App IDs in the Apple Developer portal, so
      automatic signing can issue profiles that carry the entitlements above

**The sandbox/production trap.** Debug builds get an APNs **sandbox** token; TestFlight
and App Store builds get a **production** one. Different tokens, different endpoints.
Sending to the wrong side fails as a quiet 400. FCM reads the `aps-environment`
entitlement to decide, but it does not always detect correctly — so it is set explicitly
in `ios/Runner/AppDelegate.swift`, already committed:

```swift
#if DEBUG
Messaging.messaging().setAPNSToken(deviceToken, type: .sandbox)
#else
Messaging.messaging().setAPNSToken(deviceToken, type: .prod)
#endif
```

### D.4 How the APNs half actually fits together

Worth having in your head before debugging any of it. **The app never speaks to APNs and
the backend never speaks to APNs.** There is exactly one hop each:

```
 backend ──HTTP v1──► FCM ──APNs──► device
   holds:              holds:
   service-account     your .p8
   JSON                (uploaded in D.2)
```

So each artifact has exactly one job, and putting it anywhere else is the mistake:

| Artifact | Lives where | Proves what |
|---|---|---|
| `.p8` + Key ID + Team ID | **uploaded to Firebase only** | that FCM may talk to APNs on your behalf |
| `aps-environment` entitlement | the app binary | which APNs environment the device token belongs to |
| `GoogleService-Info.plist` | the app **bundle** | which Firebase project this install belongs to |
| Service-account JSON | Secrets Manager, backend only | that the backend may call FCM |

**Test the links separately, in this order.** Each one fails differently, and testing them
together is how an afternoon disappears:

1. **Device → APNs.** Run the app, watch for `[push] token acquired`. `null`, or no line
   at all, means APNs never issued a token: D.1 or the entitlement, not Firebase.
   *Only a real device or an Apple Silicon simulator on macOS 13+ can get one.*
2. **Backend → FCM (auth).** Send to a made-up token. The correct answer is FCM rejecting
   the *token* (`INVALID_ARGUMENT`), which proves auth already worked. `403 SERVICE_DISABLED`
   or `cloudmessaging.messages.create denied` is section B, not this section.
   ```bash
   curl -XPOST -H "X-Demo-Key: $KEY" $API_BASE_URL/api/push/notification \
     -d '{"deviceId":"probe","title":"t","body":"b"}'
   ```
3. **FCM → APNs → device.** Only now send to the real token. If steps 1 and 2 passed and
   this one silently delivers nothing, it is almost always the APNs key never having been
   uploaded in D.2, or a sandbox/production mismatch — see the trap above.

Two failures that look like credentials and are not:

- **`SENDER_ID_MISMATCH`** — the plist belongs to a different Firebase app than the token.
  On this project that usually means the iOS app was not registered separately from the
  Android one. `tool/link_google_services.rb` refuses a plist whose `BUNDLE_ID` is wrong,
  which catches the common half of this.
- **Push works in debug, stops in TestFlight** — the sandbox/production trap, every time.

**Live Activities need nothing more from Apple.** The same APNs key and the same
`aps-environment` cover them. What is missing for those is on the *backend* side: FCM's
Go Admin SDK has no `live_activity_token` field, so the Live Activity endpoints have to
be raw HTTP v1 — plan v2 §5.1. The app already collects and re-sends both tokens
(`docs/screenshots/README.md` shows the screen); nothing receives them yet.

---

## Values to collect

| Value | From | Used by |
|---|---|---|
| Firebase Project ID | Firebase settings | backend (`FIREBASE_PROJECT_ID`) |
| Service account JSON | GCP IAM | backend, via Secrets Manager |
| `google-services.json` | Firebase Android app | `android/app/` |
| Function URL | `terraform output api_base_url` | app `API_BASE_URL` |
| API key | you generate it | app `API_KEY` + backend `api_key` |
| Team ID, APNs Key ID, `.p8` | Apple portal | uploaded to Firebase — **not** the backend |
| `GoogleService-Info.plist` | Firebase iOS app | Xcode, Runner target |

## Never commit

`google-services.json` · `GoogleService-Info.plist` · `firebase_options.dart` · `*.p8` ·
the service-account JSON · `terraform.tfstate` · `terraform.tfvars`

All are already in `.gitignore` in both repos, from the first commit.
