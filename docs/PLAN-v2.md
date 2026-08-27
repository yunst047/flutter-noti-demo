# Flutter Notification Demo — Implementation Plan

เอกสารนี้เป็น spec สำหรับให้ Claude Code ทำตามทีละ phase
อ่านทั้งไฟล์ก่อนเริ่ม แล้วทำทีละ phase ห้ามข้าม phase

> **v2** — อัปเดตหลังเคลียร์เรื่อง Apple Developer, การวาง credential (APNs/Firebase/AWS)
> และขอบเขตที่ simulator/emulator ทำได้

---

## 1. Goal

ทำ demo app ที่โชว์ **ทุกรูปแบบของ notification** บน Flutter ตั้งแต่ local notification
ธรรมดา ไปจนถึง Live Activity บน iOS และ Live Updates บน Android
พร้อม backend Go บน AWS ตัวเดียวที่ยิงได้ทุกแบบผ่าน FCM
เพื่อให้เห็นชัดว่า payload แต่ละแบบต่างกันตรงไหน

จุดจบของ demo คือปุ่ม **"Simulate Delivery"** ปุ่มเดียว ที่ยิง sequence ประมาณ 2 นาที
แล้วเห็น Live Activity บน iOS กับ promoted ongoing notification บน Android
อัปเดตพร้อมกันจาก server ตัวเดียวกัน

---

## 2. Constraints ที่เคลียร์แล้ว

- ✅ **มี Apple Developer Program แล้ว** → ทำได้ครบทุก phase รวม Phase 5
- **Backend host บน AWS** เป็นคนยิง FCM ทั้งหมด แอปไม่ยิง noti ข้ามเครื่องเอง
- ยิง **FCM HTTP v1 API เท่านั้น** — legacy server key ตายไปตั้งแต่ มิ.ย. 2024

ยังต้องถามผู้ใช้แล้วบันทึกลง `docs/DECISIONS.md`:
- Mac เป็น **Apple Silicon / T2** หรือเปล่า → ตัดสินว่า Phase 2–3 เทสบน simulator ได้ไหม (ดูข้อ 4)
- เครื่อง Android จริงที่มี เป็น Android เวอร์ชันอะไร
- มี iPhone จริงไหม (ต้องใช้แน่ ๆ ตอน Phase 5)
- deploy backend ด้วยอะไร — ECS Fargate / EC2 / App Runner

---

## 3. Credentials & wiring — ทำให้เสร็จก่อน Phase 2

เขียนเป็น checklist ติ๊กได้ลง `docs/SETUP.md` แล้วให้ผู้ใช้ทำมือ **อย่าเดาขั้นตอนใน console เอง**

### 3.1 Apple Developer portal

1. **Identifiers → App ID หลัก** → ติ๊ก `Push Notifications` → Save
   (Widget Extension **ไม่ต้อง**ติ๊ก)
2. **Keys → +** → ตั้งชื่อ → ติ๊ก `Apple Push Notifications service (APNs)` → Register
3. **ดาวน์โหลด `.p8`** — ได้ครั้งเดียวเท่านั้น พลาดต้องสร้าง key ใหม่
4. จดไว้: **Key ID** (10 ตัว), **Team ID**, **Bundle ID**

ใช้ Auth Key (.p8) ไม่ใช้ certificate แบบเก่า — key เดียวใช้ได้ทุกแอปใน Team และไม่หมดอายุ

### 3.2 Xcode

- Runner target → Signing & Capabilities:
  - `+ Push Notifications`
  - `+ Background Modes` → ติ๊ก **Remote notifications** (จำเป็นสำหรับ silent push) และ **Background fetch**
- `Info.plist` → `NSSupportsLiveActivities = YES`
- Widget Extension bundle ID ต้องเป็น **ลูกของ bundle ID หลัก**
  เช่น `com.you.notidemo` → `com.you.notidemo.DeliveryWidget` ผิดจากนี้ Live Activity จะไม่ทำงาน
- App Group ให้ทั้ง Runner และ widget target

**sandbox vs production — จุดที่พลาดกันบ่อยสุด**
Debug build ได้ token จาก APNs **sandbox** ส่วน TestFlight/App Store ได้ **production**
คนละ token คนละ endpoint FCM จะอ่านจาก `aps-environment` entitlement ให้ แต่บางทีตรวจไม่เจอ
ให้ระบุตรง ๆ ใน AppDelegate:

```swift
#if DEBUG
Messaging.messaging().setAPNSToken(deviceToken, type: .sandbox)
#else
Messaging.messaging().setAPNSToken(deviceToken, type: .prod)
#endif
```

### 3.3 Firebase

1. สร้าง project → register **2 apps**
   - iOS: bundle ID ต้องตรงเป๊ะ → `GoogleService-Info.plist` → **ลากเข้าผ่าน Xcode และติ๊ก target membership = Runner** (แค่วางในโฟลเดอร์ไม่พอ)
   - Android: `applicationId` → `google-services.json` → `android/app/`
2. รัน `flutterfire configure` ให้เจน `firebase_options.dart`
3. **Project settings → Cloud Messaging → Apple app configuration → upload APNs Auth Key**
   ใส่ `.p8` + Key ID + Team ID
   → นี่คือจุดที่ทำให้ FCM ยิง iOS ได้ Firebase เก็บ .p8 ไว้และคุยกับ APNs ให้
   **แปลว่า backend บน AWS ไม่ต้องมี .p8 เลย**
4. เปิด **Firebase Cloud Messaging API (V1)** ในหน้า Cloud Messaging settings
5. **สร้าง service account แยกสำหรับ backend** — อย่าใช้ "Generate new private key" ของ Firebase Admin SDK เพราะได้สิทธิ์กว้างเกิน
   - GCP Console → IAM → Service Accounts → สร้างใหม่
   - ให้ role เดียว: **`Firebase Cloud Messaging API Admin`** (`roles/firebasecloudmessaging.admin`)
     ได้แค่ `cloudmessaging.messages.create` + `fcmdata.deliverydata.list`
   - Manage keys → Add key → JSON

### 3.4 AWS

**เก็บ credential**
- service account JSON → **Secrets Manager** (secret เดียว เก็บทั้งก้อน)
- IAM role ของ ECS task / EC2 instance profile:
```json
{
  "Effect": "Allow",
  "Action": ["secretsmanager:GetSecretValue"],
  "Resource": "arn:aws:secretsmanager:ap-southeast-1:<acct>:secret:noti-demo/fcm-sa-??????"
}
```
ระบุ ARN ตรง ๆ อย่าใช้ `*` — Secrets Manager เติม suffix 6 ตัวท้ายอัตโนมัติ เลยต้องมี `??????`
**ห้าม**ใส่ JSON ลง env var หรือ bake เข้า image

**Network**
- ต้อง egress HTTPS ไป `fcm.googleapis.com` + `oauth2.googleapis.com`
- อยู่ private subnet ต้องมี NAT Gateway
- **ไม่ต้องเปิด inbound จาก Google** — FCM เป็น outbound อย่างเดียว ไม่มี webhook กลับ

### 3.5 ตารางค่าที่ต้องจด

| ค่า | เอาจากไหน | ใครใช้ |
|---|---|---|
| Team ID | Apple Developer portal | อัปเข้า Firebase |
| APNs Key ID + `.p8` | Apple → Keys | อัปเข้า Firebase (**backend ไม่ใช้**) |
| Bundle ID / applicationId | Xcode / build.gradle | ต้องตรงกับที่ register ใน Firebase |
| Firebase Project ID | Firebase settings | backend ใส่ใน URL endpoint |
| Service account JSON | GCP IAM | backend → Secrets Manager |
| Secret ARN | AWS | IAM policy ของ task role |

---

## 4. Test matrix — เทสบน sim/emulator ได้แค่ไหน

**อย่าไล่ debug บนสิ่งที่ตัวมันเองไม่รองรับ** ตารางนี้ต้องอ่านก่อนเริ่ม phase ที่เกี่ยว

### Android Emulator — ผ่านเกือบหมด

2 เงื่อนไขบังคับ:
1. ต้องใช้ system image ที่มี **Google Play Services** ("Google Play" หรือ "Google APIs")
   ถ้าเลือก AOSP เปล่า `getToken()` จะคืน null ตลอด — สาเหตุอันดับ 1 ที่คนคิดว่า FCM พัง
2. **เวลาเครื่องต้องตรง** — emulator ที่ทิ้งไว้นานแล้วเปิดใหม่ เวลาเพี้ยน → Play Services auth fail → register FCM ไม่ผ่าน แก้ด้วย cold boot

| อะไร | emulator |
|---|---|
| Local noti ทุกแบบ / action / inline reply / full-screen intent | ✅ |
| FCM push: notification, data-only, silent | ✅ |
| Live Updates (ProgressStyle) | ✅ ต้อง image **API 36+** และจะถูก *promote* จริงเฉพาะ **API 36.1 (Android 16 QPR1)** |
| Doze | จำลองได้ `adb shell dumpsys deviceidle force-idle` |
| OEM ฆ่า process (Xiaomi/Oppo/Vivo) | ❌ ต้องเครื่องจริง |
| Samsung Now Bar | ❌ |

### iOS Simulator — 3 ระดับ

**ระดับ 1 — Local notification:** ✅ ครบ ไม่มีเงื่อนไข

**ระดับ 2 — Fake push:** `xcrun simctl push <device> <bundle-id> payload.apns` หรือลากไฟล์ `.apns` ใส่
ไม่ผ่าน APNs จริง ไม่ต้องมี token ไม่ต้องมี backend
เหมาะกับเทส UI + deep link routing เร็ว ๆ และใส่ CI ได้ แต่ไม่ได้เทส token flow เลย

**ระดับ 3 — Push จริงผ่าน APNs:** ได้ ถ้าครบเงื่อนไข
- Mac **Apple Silicon หรือ T2**, macOS 13+, simulator iOS 16+
- รองรับ **sandbox เท่านั้น** → debug build เท่านั้น
- token ผูกกับคู่ (simulator + ตัวเครื่อง Mac)
- ถ้าเจอ `BadDeviceToken` ให้เช็คโค้ดแปลง token เป็น hex ก่อนโทษ simulator

**Live Activity บน simulator — ครึ่งเดียว**
- start/update จากในแอปเอง (local): ✅ และ **Dynamic Island render ได้จริง** บน sim iPhone 14 Pro ขึ้นไป → ทำ UI ได้สบาย
- update ผ่าน push: ❌ ไม่น่าเชื่อถือ log เห็น `apsd` รับ message แต่ activity ไม่โผล่ ลากไฟล์ `.apns` เพื่อ start ก็ไม่ทำงาน
- → **Phase 5 ส่วน push ต้องเครื่องจริงเท่านั้น** อย่า debug บน simulator เพราะจะแยกไม่ออกว่าพังที่โค้ดหรือที่ simulator

### สรุปต่อ phase

| Phase | iOS Simulator | Android Emulator | ต้องเครื่องจริงไหม |
|---|---|---|---|
| 0 permission | ✅ | ✅ | ไม่ |
| 1 local noti | ✅ | ✅ | ไม่ |
| 2 push พื้นฐาน | ✅ ถ้า Mac = Apple Silicon | ✅ | ไม่ (ถ้า Apple Silicon) |
| 3 rich / silent / deeplink | ⚠️ NSE ต้อง verify | ✅ | **ใช่** ตอน sign off |
| 4 Android Live Updates | — | ✅ (API 36+) | ไม่ |
| 5 Live Activity | UI ✅ / push ❌ | — | **ใช่ ตลอด phase** |
| 6 in-app / badge / log | ✅ | ⚠️ badge ขึ้นกับ launcher | ไม่ |

---

## 5. Tech stack

**Flutter app** (`app/`)
- `flutter_local_notifications` — local notification ทุกแบบ
- `firebase_core` + `firebase_messaging` — push
- `permission_handler` — runtime permission
- `flutter_timezone` + `timezone` — scheduled notification ที่ถูก timezone
- `live_activities` (pub.dev) — bridge ไป ActivityKit ฝั่ง iOS
- `go_router` — deep link จาก notification tap
- **ไม่ต้องใช้** package สำหรับ Android Live Updates — เขียน MethodChannel เอง (Phase 4)

**Backend** (`server/`) — Go + chi, deploy บน AWS
- Firebase Admin SDK Go (`firebase.google.com/go/v4`) สำหรับ push ทั่วไป
- **raw HTTP v1 สำหรับ Live Activity** (ดู 5.1)
- เก็บ token ใน memory map ก็พอ แต่แยก 3 map: `fcmTokens`, `liveActivityTokens`, `pushToStartTokens`
- ไม่ต้องมี DB

### 5.1 ข้อจำกัดที่ต้องรู้ก่อนเขียน backend

Admin SDK Go **ไม่มี field `live_activity_token`** ใน struct `ApnsConfig`
→ Phase 5 ต้องยิง raw HTTP v1 เอง:
- ขอ access token ด้วย `golang.org/x/oauth2/google` scope `https://www.googleapis.com/auth/firebase.messaging`
- POST ไป `https://fcm.googleapis.com/v1/projects/{PROJECT_ID}/messages:send`
- Admin SDK จัดการ refresh token ให้เอง (อายุ 1 ชม.) สร้าง client ครั้งเดียวตอน start ไม่ใช่ทุก request

**Native**
- Android: Kotlin — `Notification.ProgressStyle` (Phase 4)
- iOS: SwiftUI Widget Extension (Phase 5), Notification Service Extension (Phase 3)

---

## 6. Repo structure

```
noti-demo/
├── app/                          # Flutter
│   ├── lib/
│   │   ├── main.dart
│   │   ├── services/
│   │   │   ├── local_noti_service.dart
│   │   │   ├── push_service.dart
│   │   │   ├── live_activity_service.dart      # iOS
│   │   │   ├── live_update_service.dart        # Android MethodChannel
│   │   │   └── permission_service.dart
│   │   ├── screens/                            # หน้าละ 1 phase จะได้กดเทียบกันง่าย
│   │   └── widgets/in_app_banner.dart
│   ├── android/app/src/main/kotlin/.../LiveUpdatePlugin.kt
│   └── ios/
│       ├── Runner/
│       ├── NotiServiceExtension/               # Phase 3
│       └── DeliveryActivityWidget/             # Phase 5
├── server/
│   ├── main.go
│   ├── fcm/
│   │   ├── client.go                           # Admin SDK
│   │   └── rawv1.go                            # สำหรับ Live Activity
│   ├── secrets/manager.go                      # ดึง SA JSON จาก Secrets Manager
│   ├── handlers/
│   └── scenarios/delivery.go
├── infra/                                      # Dockerfile + task def / IaC
└── docs/
    ├── DECISIONS.md
    ├── SETUP.md                                # checklist ที่ต้องทำมือ (ข้อ 3)
    ├── TESTING.md                              # sim/emulator matrix (ข้อ 4)
    └── PAYLOADS.md                             # payload จริงทุกแบบไว้เทียบ
```

---

## 7. Phases

### Phase 0 — Scaffold + permission

1. `flutter create` + dependency ทั้งหมด
2. หน้า Home เป็น list ของ demo แต่ละหมวด (Local / Push / Live / Misc)
3. `permission_service.dart`:
   - Android 13+: ขอ `POST_NOTIFICATIONS` runtime
   - iOS: `requestPermission()` + แยกปุ่มทดลอง **provisional authorization** ให้เห็นความต่าง
   - Android 12+: ปุ่มพาไปหน้า setting ขอ `SCHEDULE_EXACT_ALARM`
4. หน้า Debug แสดง permission status แบบ live + FCM token + copy button

**Acceptance:** เปิดครั้งแรกบน emulator ทั้ง 2 OS แล้ว flow permission ถูกต้อง + copy FCM token ได้

---

### Phase 1 — Local notification (ไม่ต้องมี server, ไม่ต้องมีเครื่องจริง)

ทำให้ครบ แต่ละอันเป็น 1 การ์ดในหน้า Local:

1. ยิงทันที
2. ตั้งเวลา 10 วินาที (`zonedSchedule` + timezone จริงของเครื่อง)
3. ซ้ำทุกนาที + ปุ่ม cancel
4. **BigText / BigPicture / Inbox / Messaging style** (Android) — 4 ปุ่มแยก
5. Progress bar notification วิ่ง 0→100 ใน 10 วินาที
6. **Action buttons** — Accept / Decline แล้ว handle ตอนกด
7. **Inline reply** — Android `RemoteInput` / iOS `UNTextInputNotificationAction` เอาข้อความมาโชว์ในแอป
8. **Grouping** — ยิง 5 อัน + summary
9. Notification channel 3 ระดับ (high / default / low) ให้เห็นความต่างของเสียง + heads-up
10. Custom sound
11. **Full-screen intent** แบบสายเข้า (ขอ `USE_FULL_SCREEN_INTENT`)
12. **iOS interruption level** 4 แบบ (passive / active / time-sensitive / critical*)
    - critical ต้องขอ entitlement จาก Apple แยก — ทำแค่ปุ่มที่แสดง error ก็พอ

**Gotchas**
- Handler ตอนกด notification ต้องเป็น **top-level function** ที่มี `@pragma('vm:entry-point')` ไม่งั้นตอนแอปถูก kill แล้วกดจะ crash
- iOS ต้องเรียก `setForegroundNotificationPresentationOptions` ไม่งั้นตอนแอปเปิดอยู่จะไม่เห็น banner

---

### Phase 2 — Push พื้นฐาน (FCM)

> ก่อนเริ่ม: ข้อ 3 ต้องเสร็จหมดแล้ว และ backend ต้อง deploy ขึ้น AWS ได้แล้ว

**Server**
```
POST /api/tokens              # register FCM token
POST /api/push/notification   # notification message ล้วน
POST /api/push/data           # data-only message
POST /api/push/topic          # ยิงเข้า topic
```

**App**
- register token ตอนเปิดแอป + handle `onTokenRefresh`
- subscribe topic `demo-all` + ปุ่ม toggle
- handle ครบ 3 สถานะ: `onMessage` (foreground) / `onMessageOpenedApp` (background) / `getInitialMessage()` (terminated)
- หน้า Log ในแอปบันทึกทุก message ที่เข้ามา พร้อม raw payload

**เขียน `docs/PAYLOADS.md`** เทียบให้เห็นว่า notification message กับ data-only ต่างกันยังไง:
notification message ระบบเป็นคนโชว์ให้ (แอปไม่ต้องทำอะไร แต่คุม UI ไม่ได้)
data-only แอปต้องรับเองแล้วยิง local notification ต่อ (คุมได้หมด แต่โดน OEM ฆ่า process ได้)

**Gotchas**
- data-only บน Android ต้อง `"android": {"priority": "high"}` ไม่งั้นโดนดองใน Doze
- data-only บน iOS ต้อง `"apns": {"payload": {"aps": {"content-available": 1}}}` และ **ห้ามมี** `alert`
- background message handler ต้อง top-level + `@pragma('vm:entry-point')` + เรียก `Firebase.initializeApp()` ข้างใน

---

### Phase 3 — Push ขั้นสูง

```
POST /api/push/silent
POST /api/push/rich
POST /api/push/actions
POST /api/push/deeplink
```

1. **Silent push** — server ส่ง data-only → แอปตื่นมา fetch จาก `/api/inbox` → ยิง local notification ที่มีเนื้อหาจาก API เอง (pattern ที่ production ใช้จริงที่สุด)
2. **Rich push (รูป)**
   - Android: ได้ฟรีผ่าน `BigPictureStyle`
   - iOS: ต้องสร้าง target **Notification Service Extension** ใน Xcode, payload ต้องมี `"mutable-content": 1`, เขียน Swift ดาวน์โหลดรูป attach เป็น `UNNotificationAttachment`
3. **Deep link** — payload มี `{"route": "/order/123"}` → go_router พาไปหน้านั้น ต้องทำงานทั้งตอน background และตอนแอปถูก kill
4. **Notification Content Extension** (iOS, optional) — กดค้างแล้วเห็น custom SwiftUI UI

**⚠️ ปิด phase นี้ต้อง verify บนเครื่องจริง** — NSE กับ silent push ตอนแอปถูก kill บน simulator เชื่อไม่ได้

---

### Phase 4 — Android Live Updates

`flutter_local_notifications` ยังไม่รองรับ ต้องเขียน Kotlin เองผ่าน MethodChannel

**เงื่อนไขที่ระบบบังคับ (ผิดข้อเดียว = ไม่ถูก promote)**
- `compileSdk 36` ขึ้นไป
- manifest: `<uses-permission android:name="android.permission.POST_PROMOTED_NOTIFICATIONS"/>`
- style ต้องเป็น `ProgressStyle` (หรือ `BigTextStyle` / `CallStyle` / `MetricStyle`)
- ต้องเรียก `setRequestPromotedOngoing(true)`
- ต้อง `setOngoing(true)`
- ต้องมี `contentTitle`
- **ห้าม** ใช้ custom RemoteViews
- **ห้าม** เป็น group summary
- **ห้าม** `setColorized(true)`
- channel ต้องไม่ใช่ `IMPORTANCE_MIN`

**Implement**
```kotlin
// LiveUpdatePlugin.kt — MethodChannel "noti_demo/live_update"
// startDelivery(orderId, title)
// updateDelivery(orderId, step, etaText)
// endDelivery(orderId)
```
`ProgressStyle` แบ่ง 4 segment (รับออเดอร์ → ร้านกำลังทำ → ไรเดอร์รับแล้ว → กำลังไปส่ง)
ใส่ `Point` เป็นหมุดคั่นแต่ละ step + `setShortCriticalText("12 min")` สำหรับ chip บน status bar

**Runtime check ที่ต้องมี**
- `canPostPromotedNotifications()` / `hasPromotableCharacteristics()`
- บน Android 16 ที่ยังไม่ QPR1 จะ **ไม่ถูก promote** แต่ notification ยัง update in place ปกติ — **นี่คือพฤติกรรมที่ถูกต้อง ไม่ใช่ bug**
- ต่ำกว่า Android 16 → fallback ไป foreground service + ongoing notification ธรรมดา
- ถ้าผู้ใช้ปัดทิ้ง **ห้ามยิงกลับมาทันที**

**ตัวขับ:** server ส่ง data-only message แต่ละ step → แอปเรียก MethodChannel อัปเดต (ไม่ใช่ให้ server สั่ง notification ตรง)

---

### Phase 5 — iOS Live Activity + Dynamic Island

> **ต้องใช้เครื่องจริงตลอด phase นี้ในส่วน push** — simulator ทำได้แค่ UI

**ทำมือใน Xcode ก่อน (ลง `docs/SETUP.md`)**
1. เพิ่ม target **Widget Extension** ชื่อ `DeliveryActivityWidget` + ติ๊ก "Include Live Activity"
2. App Group ให้ทั้ง Runner และ widget target
3. `NSSupportsLiveActivities = YES` ใน Info.plist ของ Runner

**Swift (เขียนเอง ไม่มีทางเลี่ยง)**
- `DeliveryAttributes: ActivityAttributes` + `ContentState` (step, etaMinutes, riderName)
- Lock screen view
- Dynamic Island 3 แบบ: compact leading/trailing, expanded, minimal

**Dart** — `live_activity_service.dart`
- `createActivity()` แล้ว listen `activityUpdateStream` เอา push token ของ activity
- listen `pushToStartTokenUpdateStream` (iOS 17.2+)
- ส่ง token ทั้ง 2 แบบขึ้น server แยกกัน
- ปุ่ม update แบบ local (`updateActivity`) เทียบกับ update ผ่าน push ให้เห็นความต่าง

**Server**
```
POST /api/live-activity/token     # เก็บ activity token / push-to-start token
POST /api/live-activity/start     # push-to-start
POST /api/live-activity/update
POST /api/live-activity/end
```
ยิงผ่าน **raw HTTP v1** (Admin SDK Go ไม่รองรับ) โดยใส่ `apns.live_activity_token`
คู่กับ `message.token` ที่เป็น FCM token ปกติ
payload ต้องมี `aps.timestamp` (วินาที epoch), `aps.event` (`start`/`update`/`end`),
`aps.content-state` และตอน start ต้องมี `attributes-type` + `attributes`

**Token 3 ตัวที่ต้องแยกให้ชัด**
| token | ขอบเขต | อายุ |
|---|---|---|
| FCM registration token | ทั้งแอป | คงที่ (refresh ได้) |
| Live Activity push token | activity นั้น ๆ | **หมดอายุเมื่อ activity จบ** |
| push-to-start token | activity **type** | คงที่กว่า ใช้ start จาก server ได้ (iOS 17.2+) |

**Gotchas**
- token เปลี่ยนได้ระหว่างทาง → ต้อง listen stream ไม่ใช่เรียก `getPushToken()` ครั้งเดียว
- ลบ activity token ทิ้งทันทีเมื่อ end
- APNs sandbox (debug) vs production (release/TestFlight) ยิงผิดฝั่ง = 400 เงียบ ๆ
- iOS throttle ความถี่ push ของ Live Activity ยิงถี่เกินจะไม่ทุกอันมาถึง
- ถ้าอยากใช้ key ใหม่ของ iOS 18 (`input-push-token`) FCM อาจยังไม่รองรับ → **หยุดแล้วถามก่อน อย่าเปลี่ยนไป APNs ตรงเอง**

---

### Phase 6 — ส่วนที่เหลือ + ตัวจบ

1. **In-app banner** — overlay widget ในแอปเอง (ไม่ใช่ OS notification) ให้เห็นว่าคนละเรื่องกัน
2. **Badge count** บน app icon + ปุ่ม clear (Android ขึ้นกับ launcher — บันทึกว่ารุ่นไหนขึ้น/ไม่ขึ้น)
3. **หน้า Log** — บันทึกทุก event (received / displayed / tapped / dismissed) พร้อม timestamp
4. **ปุ่ม Simulate Delivery** — `POST /api/simulate/delivery`
   server รัน goroutine ยิง 4 step ห่างกัน 20 วินาที เข้าทั้ง iOS Live Activity และ Android Live Update พร้อมกัน แล้วปิดท้ายด้วย end
5. เขียน `docs/PAYLOADS.md` ให้ครบทุกแบบ — **deliverable ที่มีค่าที่สุดของ demo นี้**

---

## 8. กติกาสำหรับ Claude Code

- ทำทีละ phase แล้วหยุดให้ผู้ใช้ทดสอบก่อนไป phase ถัดไป
- **อย่าเดา** ขั้นตอนใน Firebase Console / Apple Developer portal / Xcode / AWS Console —
  เขียนเป็น checklist ลง `docs/SETUP.md` ให้ผู้ใช้ทำมือ แล้วรอ confirm
- ก่อนเริ่ม phase ที่เกี่ยวกับ push ให้เช็คตารางข้อ 4 ก่อนว่าเทสบน sim/emulator ได้ไหม
  ถ้าไม่ได้ให้บอกผู้ใช้ตรง ๆ ว่าต้องใช้เครื่องจริง **ห้ามไล่ debug บน simulator ในส่วนที่ simulator ไม่รองรับ**
- ทุก payload ที่ส่งจาก server ให้ log ออกมาแบบ pretty JSON เสมอ — นี่คือแก่นของ demo
- **ห้าม commit**: service account JSON, `GoogleService-Info.plist`, `google-services.json`, `.p8`
  ใส่ `.gitignore` ตั้งแต่ commit แรก และให้อ่านจาก Secrets Manager / env
- Phase 4 และ 5 ต้องมี **runtime capability check** เสมอ เครื่องที่ไม่รองรับต้อง degrade
  ลงมาเป็น notification ธรรมดา ไม่ใช่ crash
- เขียน `docs/DECISIONS.md` บันทึกทุกจุดที่ตัดสินใจแทนผู้ใช้ไป
