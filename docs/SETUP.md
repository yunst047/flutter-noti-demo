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

## D. Apple  ⏸ deferred — needs the Mac

Unblocks: anything iOS. Nothing here can be done from Windows, and none of it blocks
Android work.

### D.1 Apple Developer portal

- [ ] **Identifiers → App ID** for `com.f0h.flt-noti-demo` → enable **Push Notifications**
      → Save. The Widget Extension does **not** need this ticked.
- [ ] **Keys → +** → name it → enable **Apple Push Notifications service (APNs)** →
      Register
- [ ] **Download the `.p8`** — available exactly once. Miss it and you must create a new
      key.

**Collect:** **Key ID** (10 chars), **Team ID**, **Bundle ID**.

Use the Auth Key (`.p8`), not the older certificate flow: one key covers every app in the
team and never expires.

### D.2 Firebase — iOS

- [ ] Add an iOS app to the same Firebase project, bundle ID `com.f0h.flt-noti-demo`
- [ ] `GoogleService-Info.plist` → **drag into Xcode and tick target membership = Runner**.
      Copying the file into the folder is not enough; it must be in the target.
- [ ] **Project settings → Cloud Messaging → Apple app configuration → upload the APNs
      Auth Key** with Key ID + Team ID

> This is what lets FCM reach iOS. Firebase holds the `.p8` and talks to APNs for you,
> which means **the AWS backend never needs the `.p8` at all**.

### D.3 Xcode

- [ ] Runner target → Signing & Capabilities → add **Push Notifications**
- [ ] Add **Background Modes** → tick **Remote notifications** (required for silent push)
      and **Background fetch**
- [ ] `Info.plist` → `NSSupportsLiveActivities = YES`
- [ ] Widget Extension bundle ID must be a **child** of the main bundle ID —
      `com.f0h.flt-noti-demo.DeliveryWidget`. Anything else and Live Activities silently
      will not work.
- [ ] App Group shared by both the Runner and widget targets

**The sandbox/production trap.** Debug builds get an APNs **sandbox** token; TestFlight
and App Store builds get a **production** one. Different tokens, different endpoints.
Sending to the wrong side fails as a quiet 400. FCM reads the `aps-environment`
entitlement to decide, but it does not always detect correctly — set it explicitly in
`AppDelegate`:

```swift
#if DEBUG
Messaging.messaging().setAPNSToken(deviceToken, type: .sandbox)
#else
Messaging.messaging().setAPNSToken(deviceToken, type: .prod)
#endif
```

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
